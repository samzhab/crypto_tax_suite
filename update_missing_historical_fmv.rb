require 'csv'
require 'yaml'
require 'date'

FMV_FILE = 'cache/historical_fmv_ton_cad.yaml'
CSV_FOLDER = 'CRA_Reports'

# Load FMV data with date strings converted to Date objects
fmv_data = if File.exist?(FMV_FILE)
  YAML.safe_load(File.read(FMV_FILE), permitted_classes: [Date, Symbol], aliases: true)
            .transform_keys { |k| Date.parse(k.to_s) rescue k } || {}
else
  puts "Error: #{FMV_FILE} not found!"
  exit 1
end

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

total_updates = 0
total_files_checked = 0
total_files_updated = 0
total_na_values_found = 0

# Process each latest wallet file
wallet_files.each_value do |files|
  latest_file = files.max_by { |f| f[:timestamp] }
  file_path = latest_file[:path]
  total_files_checked += 1

  puts "\nProcessing: #{file_path}"

  begin
    rows = CSV.read(file_path, headers: true)
    headers = rows.headers

    unless headers.include?('Date (UTC)') && headers.include?('CAD Value')
      puts "  ! Required columns not found in file"
      next
    end

    changed = false
    file_updates = 0
    file_na_values = 0

    rows.each do |row|
      date_str = row['Date (UTC)']
      cad_value = row['CAD Value']

      if cad_value.to_s.strip.upcase == 'N/A'
        file_na_values += 1
        total_na_values_found += 1

        unless date_str
          puts "    ! Missing date for N/A value"
          next
        end

        begin
          date = Date.parse(date_str)

          # Check FMV data with date as both Date and String
          if fmv_data.key?(date) || fmv_data.key?(date.to_s)
            fmv_value = fmv_data[date] || fmv_data[date.to_s]
            new_value = fmv_value.round(4).to_s
            row['CAD Value'] = new_value
            changed = true
            file_updates += 1
            total_updates += 1
            puts "    ✓ Updated #{date}: #{new_value} CAD"
          else
            puts "    ✗ No FMV data for #{date} (checked as Date and String)"
            puts "    Available dates around this date:"
            fmv_data.keys.sort.each do |k|
              if (k.to_date - date).abs <= 3
                puts "      - #{k}: #{fmv_data[k]}"
              end
            end
          end
        rescue ArgumentError => e
          puts "    ! Invalid date format: #{date_str}"
          next
        end
      end
    end

    if changed
      CSV.open(file_path, 'w') do |csv|
        csv << headers
        rows.each { |r| csv << r }
      end
      total_files_updated += 1
      puts "  ✓ Updated #{file_updates}/#{file_na_values} N/A values"
    else
      if file_na_values > 0
        puts "  ✗ Found #{file_na_values} N/A values but no matching FMV data"
      else
        puts "  No N/A values found in file"
      end
    end
  rescue => e
    puts "  ! Error processing file: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    next
  end
end

puts "\nUpdate summary:"
puts "  - Files checked: #{total_files_checked}"
puts "  - Total N/A values found: #{total_na_values_found}"
puts "  - Files updated: #{total_files_updated}"
puts "  - Total CAD values updated: #{total_updates}"

if total_na_values_found > 0 && total_updates == 0
  puts "\nWarning: Found #{total_na_values_found} N/A values but couldn't update any!"
  puts "Possible reasons:"
  puts "1. Dates in CSV don't match dates in #{FMV_FILE}"
  puts "2. #{FMV_FILE} is missing data for these dates"
  puts "3. Date formats don't match between files"
end
