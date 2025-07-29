require 'csv'
require 'yaml'
require 'time'
require 'date'

MISSING_FILE = 'missing_historical_fmv_dates.yaml'
FMV_FILE = 'cache/historical_fmv_ton_cad.yaml'
CSV_FOLDER = 'CRA_Reports'

# Load existing FMV data
fmv_data = if File.exist?(FMV_FILE)
  YAML.safe_load(File.read(FMV_FILE), permitted_classes: [Date, Symbol], aliases: true) || {}
else
  {}
end

# Load existing missing dates
existing_missing = if File.exist?(MISSING_FILE)
  YAML.safe_load(File.read(MISSING_FILE), permitted_classes: []) || []
else
  []
end

# Convert all dates to strings for comparison
missing_dates = existing_missing.map(&:to_s)

# Check if CSV folder exists
unless Dir.exist?(CSV_FOLDER)
  puts "Error: CSV folder '#{CSV_FOLDER}' not found!"
  exit 1
end

# Find latest version of each wallet file
wallet_files = Hash.new { |h, k| h[k] = [] }

Dir.glob("#{CSV_FOLDER}/cra_fmv_*_*.csv").each do |file|
  next unless file.match?(/cra_fmv_(.+?)_(\d{8}_\d{6})\.csv$/)
  wallet_id = $1
  timestamp = $2
  wallet_files[wallet_id] << { path: file, timestamp: timestamp }
end

# Process only the latest version of each wallet file
wallet_files.each_value do |files|
  latest_file = files.max_by { |f| f[:timestamp] }
  file_path = latest_file[:path]

  puts "Processing latest wallet file: #{file_path}"

  begin
    CSV.foreach(file_path, headers: true) do |row|
      date_str = row['Date (UTC)']
      cad_value = row['CAD Value']

      # Skip if no date or CAD value exists
      next unless date_str && cad_value == 'N/A'

      begin
        date = Date.parse(date_str)
        date_key = date.to_s

        # Add to missing dates if not in FMV data (regardless of age)
        unless fmv_data.key?(date) || missing_dates.include?(date_key)
          missing_dates << date_key
          puts "  + Found missing FMV for #{date_key}"
        end
      rescue ArgumentError => e
        puts "  ! Invalid date format in #{file_path}: #{date_str} (#{e.message})"
        next
      end
    end
  rescue => e
    puts "  ! Error processing #{file_path}: #{e.message}"
    next
  end
end

# Sort and deduplicate
missing_dates.uniq!
missing_dates.sort!

if missing_dates.empty?
  puts "No missing FMV dates found in any CSV files."
else
  puts "Found #{missing_dates.size} missing FMV dates. Updating #{MISSING_FILE}..."
  File.write(MISSING_FILE, missing_dates.to_yaml)
  puts "Missing dates saved to #{MISSING_FILE}"
end
