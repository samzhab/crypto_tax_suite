require 'yaml'
require 'httparty'
require 'digest'
require 'parallel'
require 'date'
require 'fileutils'

# Configuration
COINGECKO_API_KEY = 'XXX' # your CoinGecko API key here
COINGECKO_API_URL = 'https://api.coingecko.com/api/v3'
CACHE_DIR = 'cache'
LOG_DIR = 'logs'
PROCESSED_DIR = 'Processed'
FMV_OUTPUT_DIR = "#{PROCESSED_DIR}/FMV_values"
MIN_API_INTERVAL = 13.0 # seconds (max 10 calls/minute)
MAX_RETRIES = 3
MAX_THREADS = 4
MAX_HISTORY_DAYS = 365

CHAIN_MAPPING = {
  # 'OPTIMISM' => { id: 'optimism', currency: 'cad' },
  # 'BSC' => { id: 'binancecoin', currency: 'cad' },
  # 'ETH' => { id: 'ethereum', currency: 'cad' },
  # 'TON' => { id: 'the-open-network', currency: 'cad' },
  # 'TRON' => { id: 'tron', currency: 'cad' },
  'SOL' => { id: 'solana', currency: 'cad' }
  # 'ARB' => { id: 'arbitrum', currency: 'cad' },
  # 'COREDAO' => { id: 'coredao', currency: 'cad' },
  # 'BASE' => { id: 'base', currency: 'cad' },
  # 'OPBNB' => { id: 'opbnb-bridged-wbnb-opbnb', currency: 'cad' },
  # 'SCROLL' => { id: 'scroll', currency: 'cad' },
  # 'LINEA' => { id: 'linea', currency: 'cad' },
  # 'SONIC' => { id: 'sonic', currency: 'cad' }
  # 'ZKSYNC' => { id: 'zksync', currency: 'cad' }
}

class RateLimiter
  def initialize(interval)
    @interval = interval
    @mutex = Mutex.new
    @last_call = Time.now - interval
  end

  def wait
    @mutex.synchronize do
      elapsed = Time.now - @last_call
      sleep_time = @interval - elapsed
      if sleep_time > 0
        log("Rate limiting - sleeping #{sleep_time.round(2)}s")
        sleep(sleep_time)
      end
      @last_call = Time.now
    end
  end
end

$rate_limiter = RateLimiter.new(MIN_API_INTERVAL)

def log(message, level=:info)
  timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
  prefix = case level
           when :error then "\e[31m[ERROR]"
           when :warn then "\e[33m[WARN]"
           else "[INFO]"
           end
  puts "#{prefix} #{timestamp} - #{message}\e[0m"

  begin
    FileUtils.mkdir_p(LOG_DIR)
    File.open("#{LOG_DIR}/processing_#{Date.today}.log", 'a') { |f| f.puts "#{timestamp} #{level.upcase} #{message}" }
  rescue
    # ignore logging errors
  end
end

def fetch_historical_price(coin_id, date, currency)
  retries = 0
  while retries <= MAX_RETRIES
    $rate_limiter.wait
    begin
      log("Fetching price for #{coin_id} on #{date}")
      response = HTTParty.get(
        "#{COINGECKO_API_URL}/coins/#{coin_id}/history",
        query: { date: date.strftime('%d-%m-%Y'), localization: false },
        headers: { 'x_cg_demo_api_key' => COINGECKO_API_KEY },
        timeout: 15
      )
      case response.code
      when 200
        price = response.dig('market_data', 'current_price', currency)
        if price
          log("Price fetched: #{price} #{currency.upcase} on #{date}")
          return price.to_f
        else
          log("No price data available for #{coin_id} on #{date}", :warn)
          return nil
        end
      when 429
        wait_time = 10 * (2 ** retries)
        log("Rate limited by API, sleeping for #{wait_time}s", :warn)
        sleep(wait_time)
      else
        log("API returned HTTP #{response.code}", :warn)
      end
    rescue StandardError => e
      log("Error fetching price: #{e.message}", :error)
    end
    retries += 1
    sleep(5 * retries)
  end
  log("Failed to fetch price for #{coin_id} on #{date} after #{MAX_RETRIES} retries", :error)
  nil
end

def process_yaml_file(chain, file_path)
  chain_key = chain.upcase
  unless CHAIN_MAPPING.key?(chain_key)
    log("Unknown chain: #{chain_key}, skipping file #{file_path}", :warn)
    return
  end

  coin_id = CHAIN_MAPPING[chain_key][:id]
  currency = CHAIN_MAPPING[chain_key][:currency]

  log("Processing file #{file_path} for chain #{chain_key}")

  yaml_data = YAML.load_file(file_path)
  # Transactions are under :transactions key, each with a :date string

  transactions = yaml_data[:transactions]
  return unless transactions.is_a?(Array)

  dates = transactions.map { |tx| Date.parse(tx[:date]) rescue nil }.compact.uniq

  # Only consider dates within MAX_HISTORY_DAYS
  cutoff_date = Date.today - MAX_HISTORY_DAYS
  valid_dates = dates.select { |d| d >= cutoff_date }

  fmv_cache = {}
  cache_file = "#{CACHE_DIR}/fmv_cache_#{coin_id}.yaml"
  if File.exist?(cache_file)
    fmv_cache = YAML.load_file(cache_file) || {}
  end

  new_rates = {}

  valid_dates.each do |date|
    date_str = date.to_s
    if fmv_cache.key?(date_str)
      log("Using cached FMV for #{date_str}")
      new_rates[date_str] = fmv_cache[date_str]
    else
      price = fetch_historical_price(coin_id, date, currency)
      if price
        new_rates[date_str] = price
        fmv_cache[date_str] = price
      else
        log("Missing FMV for #{date_str}")
      end
    end
  end

  # Save updated cache for this coin
  FileUtils.mkdir_p(CACHE_DIR)
  File.write(cache_file, fmv_cache.to_yaml)

  # Now add FMV to each transaction (or nil if not found)
  transactions.each do |tx|
    date_str = tx[:date]
    tx[:fmv_cad] = new_rates[date_str] || nil
  end

  # Prepare output directory and filename
  relative_path = file_path.sub("#{PROCESSED_DIR}/#{chain_key.downcase}/", '')
  output_dir = "#{FMV_OUTPUT_DIR}/#{chain_key.downcase}"
  FileUtils.mkdir_p(output_dir)
  output_path = "#{output_dir}/#{File.basename(file_path)}"

  # Save new YAML with FMV added
  File.write(output_path, yaml_data.to_yaml)

  log("Saved FMV enriched file to #{output_path}")
end

def main
  ensure_dirs = [LOG_DIR, CACHE_DIR, FMV_OUTPUT_DIR].each do |d|
    FileUtils.mkdir_p(d)
  end

  # For each chain folder inside Processed, find all .yaml files and process
  Dir.glob("#{PROCESSED_DIR}/*").select { |f| File.directory?(f) }.each do |chain_dir|
    chain_name = File.basename(chain_dir)
    yaml_files = Dir.glob("#{chain_dir}/*.yaml")

    log("Found #{yaml_files.size} YAML files for chain #{chain_name}")

    Parallel.each(yaml_files, in_threads: MAX_THREADS) do |file_path|
      process_yaml_file(chain_name, file_path)
    end
  end

  log("All files processed.")
end

main
