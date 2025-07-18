require 'yaml'
require 'fileutils'

# Ensure log directory exists
FileUtils.mkdir_p('Processed/TON/Logs')

# Open log file
File.open('Processed/TON/Logs/ton_values_report.log', 'w') do |log|
  # Process each YAML file
  Dir.glob('Processed/TON/YAML/*.yaml').each do |file|
    yaml = YAML.load_file(file)
    wallet = yaml[:wallet]
    log.puts(":wallet: #{wallet}")

    # Extract TON values from transactions with transaction numbering
    yaml[:transactions].each_with_index do |txn, index|
      ton_value = txn[:details].find { |detail| detail.to_s.include?('TON') }
      log.puts(":transaction_#{index + 1}: #{ton_value}") if ton_value
    end
    log.puts("\n")
  end
end
