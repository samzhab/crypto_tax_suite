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
      details = txn[:details]
      if details.is_a?(Array)
        ton_value = details.find { |detail| detail.to_s.include?('TON') }
        log.puts(":transaction_#{index + 1}: #{ton_value}") if ton_value
      else
        log.puts(":transaction_#{index + 1}: no details array")
      end
    end

    log.puts("\n")
  end
end
