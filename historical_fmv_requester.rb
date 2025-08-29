require 'yaml'
require 'httparty'
require 'digest'
require 'parallel'
require 'date'
require 'fileutils'
require 'byebug'


# Config
COINGECKO_API_KEY = 'XXX'
COINGECKO_API_URL = 'https://api.coingecko.com/api/v3'
CACHE_DIR = 'cache'
LOG_DIR = 'logs'
PROCESSED_DIR = 'Processed'
FMV_OUTPUT_FILE = "#{PROCESSED_DIR}/FMV_values/multi_chain_fmv_cad.yaml"
MIN_API_INTERVAL = 13.0
MAX_RETRIES = 3
MAX_THREADS = 4
MAX_HISTORY_DAYS = 365

CHAIN_MAPPING = {
  # 'OPTIMISM' => { id: 'optimism', currency: 'cad' },
  'BSC' => { id: 'binancecoin', currency: 'cad' },
  'ETH' => { id: 'ethereum', currency: 'cad' },
  'TON' => { id: 'the-open-network', currency: 'cad' },
  'TRON' => { id: 'tron', currency: 'cad' },
  'SOL' => { id: 'solana', currency: 'cad' },
  'ARB' => { id: 'arbitrum', currency: 'cad' },
  'COREDAO' => { id: 'coredao', currency: 'cad' },
  'BASE' => { id: 'ethereum', currency: 'cad' },
  'OPBNB' => { id: 'opbnb-bridged-wbnb-opbnb', currency: 'cad' },
  'SCROLL' => { id: 'scroll', currency: 'cad' },
  # 'LINEA' => { id: 'linea', currency: 'cad' },
  # 'SONIC' => { id: 'sonic', currency: 'cad' },
  'ZKSYNC' => { id: 'zksync', currency: 'cad' }
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
    File.open("#{LOG_DIR}/processing_#{Date.today}.log", 'a') do |f|
      f.puts "#{timestamp} #{level.upcase} #{message}"
    end
  rescue
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
        return price.to_f if price
        log("No price data for #{coin_id} on #{date}", :warn)
        return nil
      when 429
        wait_time = 10 * (2 ** retries)
        log("Rate limited by API, sleeping #{wait_time}s", :warn)
        sleep(wait_time)
      else
        log("API returned #{response.code}", :warn)
      end
    rescue => e
      log("Error fetching price: #{e.message}", :error)
    end
    retries += 1
    sleep(5 * retries)
  end
  log("Failed to fetch price for #{coin_id} on #{date}", :error)
  nil
end

def process_yaml_file(chain, file_path, global_fmv_data)
  chain_key = chain.upcase
  return unless CHAIN_MAPPING.key?(chain_key)

  coin_id = CHAIN_MAPPING[chain_key][:id]
  currency = CHAIN_MAPPING[chain_key][:currency]

  yaml_data = YAML.load_file(file_path)
  transactions = yaml_data[:transactions]
  return unless transactions.is_a?(Array)

  dates = transactions.map { |tx| Date.parse(tx[:date]) rescue nil }.compact.uniq
  cutoff_date = Date.today - MAX_HISTORY_DAYS
  valid_dates = dates.select { |d| d >= cutoff_date }

  fmv_cache_file = "#{CACHE_DIR}/fmv_cache_#{coin_id}.yaml"
  fmv_cache = File.exist?(fmv_cache_file) ? YAML.load_file(fmv_cache_file) || {} : {}
  global_fmv_data[chain_key] ||= {}

  valid_dates.each do |date|
    date_str = date.to_s
    if fmv_cache.key?(date_str)
      log("Using cached FMV for #{chain_key} #{date_str}")
      global_fmv_data[chain_key][date_str] = fmv_cache[date_str]
    else
      price = fetch_historical_price(coin_id, date, currency)
      if price
        fmv_cache[date_str] = price
        global_fmv_data[chain_key][date_str] = price
      else
        log("Missing FMV for #{chain_key} #{date_str}")
      end
    end
  end

  FileUtils.mkdir_p(CACHE_DIR)
  File.write(fmv_cache_file, fmv_cache.to_yaml)
end

def main
  FileUtils.mkdir_p([LOG_DIR, CACHE_DIR, File.dirname(FMV_OUTPUT_FILE)])

  global_fmv_data = {}

  Dir.glob("#{PROCESSED_DIR}/*").select { |f| File.directory?(f) }.each do |chain_dir|
    chain_name = File.basename(chain_dir).upcase
    next unless CHAIN_MAPPING.key?(chain_name)

    yaml_files = Dir.glob("#{chain_dir}/*.yaml")
    log("Found #{yaml_files.size} YAML files for #{chain_name}")

    Parallel.each(yaml_files, in_threads: MAX_THREADS) do |file_path|
      process_yaml_file(chain_name, file_path, global_fmv_data)
    end
  end

  File.write(FMV_OUTPUT_FILE, global_fmv_data.to_yaml)
  log("Saved multi-chain FMV CAD data to #{FMV_OUTPUT_FILE}")
end

main
