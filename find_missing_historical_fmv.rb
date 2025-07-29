require 'yaml'
require 'date'
require 'httparty'

MISSING_FILE = 'missing_historical_fmv_dates.yaml'
FMV_FILE = 'historical_fmv_ton_cad.yaml'
COINGECKO_API_URL = 'https://api.coingecko.com/api/v3'
COINGECKO_API_KEY = 'XXXX' # Replace with your actual key
MIN_API_CALL_INTERVAL = 20 # seconds

# Load files
missing_dates = if File.exist?(MISSING_FILE)
  YAML.safe_load(File.read(MISSING_FILE), permitted_classes: []) || []
else
  puts "No missing dates file found. Nothing to do."
  exit 0
end

fmv_data = if File.exist?(FMV_FILE)
  YAML.safe_load(File.read(FMV_FILE), permitted_classes: [Date, Symbol], aliases: true) || {}
else
  {}
end

today = Date.today
updated_dates = []
skipped_dates = []
failed_dates = []

# Process missing dates
missing_dates.each do |date_str|
  begin
    date = Date.parse(date_str)
    next if fmv_data.key?(date) # Skip if already exists

    if (today - date).to_i > 365
      puts "Skipping date older than 365 days: #{date_str}"
      skipped_dates << date_str
      next
    end

    puts "Fetching FMV for #{date_str}..."
    response = HTTParty.get(
      "#{COINGECKO_API_URL}/coins/the-open-network/history",
      query: { date: date.strftime('%d-%m-%Y'), localization: false },
      headers: { 'x_cg_demo_api_key' => COINGECKO_API_KEY }
    )

    if response.success?
      price = response.dig('market_data', 'current_price', 'cad')
      if price
        fmv_data[date] = price.to_f
        updated_dates << date_str
        puts "  ✓ Found FMV: #{price} CAD"
      else
        puts "  ✗ Price not available for #{date_str}"
        failed_dates << date_str
      end
    else
      puts "  ✗ API Error: #{response.code} - #{response.body}"
      failed_dates << date_str
    end

    sleep MIN_API_CALL_INTERVAL
  rescue ArgumentError => e
    puts "  ! Invalid date format: #{date_str} (#{e.message})"
    next
  rescue => e
    puts "  ! Error processing #{date_str}: #{e.message}"
    failed_dates << date_str
    next
  end
end

# Save FMV updates if we have any new data
if updated_dates.any?
  File.write(FMV_FILE, fmv_data.transform_keys(&:to_s).sort.to_h.to_yaml)
  puts "Updated #{updated_dates.size} FMV entries in #{FMV_FILE}"
end

# Update missing dates file
remaining_dates = (missing_dates - updated_dates).uniq.sort

if remaining_dates.empty?
  File.delete(MISSING_FILE) if File.exist?(MISSING_FILE)
  puts "All missing FMV dates resolved. Removed #{MISSING_FILE}."
else
  File.write(MISSING_FILE, remaining_dates.to_yaml)
  puts "#{remaining_dates.size} dates remain unresolved in #{MISSING_FILE}:"
  puts "  - #{remaining_dates.join("\n  - ")}"
end

# Summary
puts "\nOperation summary:"
puts "  - Successfully fetched: #{updated_dates.size}"
puts "  - Skipped (older than 365 days): #{skipped_dates.size}"
puts "  - Failed to fetch: #{failed_dates.size}"
