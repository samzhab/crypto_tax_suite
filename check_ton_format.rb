require 'yaml'
require 'find'

# Method to extract the total TON value from the YAML file (sum all TON values)
def extract_ton_from_yaml(yaml_file_path)
  begin
    yaml_data = YAML.load_file(yaml_file_path)

    # Print the loaded YAML data to see its structure (for debugging)
    # puts "YAML Data Loaded: #{yaml_data.inspect}"

    # Extract the list of transactions
    transactions = yaml_data[:transactions]  # Using symbol keys as per your YAML structure

    # If the transactions key doesn't exist or is nil, handle it gracefully
    if transactions.nil?
      puts "Warning: No transactions found in YAML file: #{yaml_file_path}"
      return 0.0
    end

    total_ton = 0

    # Iterate through each transaction and extract the TON values from :details
    transactions.each do |txn|
      txn[:details].each do |detail|
        # We expect values like "+ 0 TON", "− 4.96 TON", "+ 5.00 TON", etc.
        if detail =~ /([+-]?\s?\d+\.?\d*)\s?TON/  # Regex to capture both + and − values
          total_ton += $1.to_f
        end
      end
    end

    total_ton
  rescue => e
    puts "Error processing YAML file #{yaml_file_path}: #{e.message}"
    return 0.0
  end
end

# Method to extract the total TON value from the TXT file (sum all TON values)
def extract_ton_from_txt(txt_file_path)
  total_ton = 0

  # Read the TXT file and extract all TON values (positive and negative)
  File.readlines(txt_file_path).each do |line|
    # Regex to capture both positive and negative TON values (e.g., "+ 5.00 TON" or "− 4.96 TON")
    if line =~ /([+-]?\s?\d+\.?\d*)\s?TON/
      total_ton += $1.to_f
    end
  end

  total_ton
end

# Method to compare all YAML and TXT files in their respective directories
def compare_files(yaml_dir, txt_dir, log_file_path)
  # Open the log file for writing
  log_file = File.open(log_file_path, 'w')

  # Write the header for the log file
  log_file.puts("Comparison Log - #{Time.now}")
  log_file.puts("-" * 50)

  total_net_ton = 0 # To track the total net value for all comparisons

  # Loop through each YAML file in the YAML directory and find the corresponding TXT file
  Find.find(yaml_dir) do |yaml_file|
    next unless yaml_file =~ /.yaml$/  # Skip non-YAML files

    # Construct the corresponding TXT file path by adding "TON_" prefix
    filename_without_extension = File.basename(yaml_file, ".yaml")
    txt_filename = "TON_#{filename_without_extension}.txt"
    txt_file = File.join(txt_dir, txt_filename)

    # Check if the TXT file exists
    if File.exist?(txt_file)
      # Extract TON values from both files
      yaml_ton_value = extract_ton_from_yaml(yaml_file)
      txt_ton_value = extract_ton_from_txt(txt_file)

      # Compare the TON values
      if yaml_ton_value == txt_ton_value
        log_file.puts("MATCH: #{yaml_file} <-> #{txt_file}")
        log_file.puts("    YAML Value: #{yaml_ton_value}")
        log_file.puts("    TXT Value: #{txt_ton_value}")
        log_file.puts("-" * 50)

        total_net_ton += yaml_ton_value
        puts "MATCH for #{yaml_file} and #{txt_file}: #{yaml_ton_value} TON"
      else
        log_file.puts("MISMATCH: #{yaml_file} <-> #{txt_file}")
        log_file.puts("    YAML Value: #{yaml_ton_value}")
        log_file.puts("    TXT Value: #{txt_ton_value}")
        log_file.puts("-" * 50)

        total_net_ton += yaml_ton_value
        puts "MISMATCH for #{yaml_file} and #{txt_file}:"
        puts "    YAML Value: #{yaml_ton_value}, TXT Value: #{txt_ton_value}"
      end
    else
      log_file.puts("WARNING: No corresponding TXT file found for #{yaml_file}. Expected: #{txt_file}")
      log_file.puts("-" * 50)
      puts "Warning: No corresponding TXT file found for #{yaml_file}. Expected: #{txt_file}"
    end
  end

  # Write the total net TON value to the log file
  log_file.puts("TOTAL NET TON: #{total_net_ton}")
  log_file.puts("-" * 50)

  # Close the log file
  log_file.close

  # Output the total net TON to the screen
  puts "Total Net TON: #{total_net_ton}"
end

# Specify the directories containing the YAML and TXT files
yaml_directory = "Processed/TON/YAML"
txt_directory = "CSV_Dumps/TON"
log_file_path = "comparison_log.txt"  # Path to the log file

# Call the comparison method
compare_files(yaml_directory, txt_directory, log_file_path)
