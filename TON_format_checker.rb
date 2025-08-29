require 'yaml'
require 'find'

class TONFormatChecker
  TON_PATTERN = /([+-]?\s?\d+\.?\d*)\s?TON/i.freeze

  def self.extract_ton_from_yaml(yaml_file_path)
    begin
      yaml_data = YAML.load_file(yaml_file_path)
      transactions = yaml_data[:transactions] || yaml_data['transactions']

      return 0.0 if transactions.nil? || transactions.empty?

      transactions.sum do |txn|
        details = txn[:details] || txn['details'] || []
        details.sum { |detail| extract_value_from_string(detail.to_s) }
      end

    rescue StandardError => e
      puts "Error processing YAML file #{yaml_file_path}: #{e.message}"
      0.0
    end
  end

  def self.extract_ton_from_txt(txt_file_path)
    return 0.0 unless File.exist?(txt_file_path)

    File.readlines(txt_file_path).sum do |line|
      extract_value_from_string(line)
    end
  end

  def self.extract_value_from_string(text)
    text.scan(TON_PATTERN).sum do |match|
      value = match[0].gsub(/\s+/, '').to_f
      value
    end
  end

  def self.compare_files(yaml_dir, txt_dir, log_file_path)
    total_net_ton = 0
    mismatches = []

    File.open(log_file_path, 'w') do |log_file|
      write_log_header(log_file)

      Find.find(yaml_dir) do |yaml_file|
        next unless yaml_file.end_with?('.yaml')

        txt_file = find_corresponding_txt(yaml_file, txt_dir)

        if File.exist?(txt_file)
          process_file_pair(yaml_file, txt_file, log_file, total_net_ton, mismatches)
        else
          log_missing_file(log_file, yaml_file, txt_file)
        end
      end

      write_summary(log_file, total_net_ton, mismatches)
    end

    puts "Total Net TON: #{total_net_ton}"
    puts "Mismatches found: #{mismatches.size}" if mismatches.any?
  end

  private

  def self.find_corresponding_txt(yaml_file, txt_dir)
    filename = "TON_#{File.basename(yaml_file, '.yaml')}.txt"
    File.join(txt_dir, filename)
  end

  def self.process_file_pair(yaml_file, txt_file, log_file, total_net_ton, mismatches)
    yaml_value = extract_ton_from_yaml(yaml_file)
    txt_value = extract_ton_from_txt(txt_file)

    if (yaml_value - txt_value).abs < 0.001 # Floating point tolerance
      log_match(log_file, yaml_file, txt_file, yaml_value, txt_value)
      total_net_ton += yaml_value
    else
      log_mismatch(log_file, yaml_file, txt_file, yaml_value, txt_value)
      mismatches << { yaml: yaml_file, txt: txt_file, diff: (yaml_value - txt_value).abs }
      total_net_ton += yaml_value
    end
  end

  def self.write_log_header(log_file)
    log_file.puts("Comparison Log - #{Time.now}")
    log_file.puts("-" * 50)
  end

  def self.log_match(log_file, yaml_file, txt_file, yaml_value, txt_value)
    log_file.puts("MATCH: #{File.basename(yaml_file)} <-> #{File.basename(txt_file)}")
    log_file.puts("    YAML Value: #{'%.2f' % yaml_value}")
    log_file.puts("    TXT Value: #{'%.2f' % txt_value}")
    log_file.puts("-" * 50)
    puts "MATCH: #{File.basename(yaml_file)} - #{'%.2f' % yaml_value} TON"
  end

  def self.log_mismatch(log_file, yaml_file, txt_file, yaml_value, txt_value)
    log_file.puts("MISMATCH: #{File.basename(yaml_file)} <-> #{File.basename(txt_file)}")
    log_file.puts("    YAML Value: #{'%.2f' % yaml_value}")
    log_file.puts("    TXT Value: #{'%.2f' % txt_value}")
    log_file.puts("    Difference: #{'%.2f' % (yaml_value - txt_value).abs}")
    log_file.puts("-" * 50)
    puts "MISMATCH: #{File.basename(yaml_file)} - Diff: #{'%.2f' % (yaml_value - txt_value).abs} TON"
  end

  def self.log_missing_file(log_file, yaml_file, txt_file)
    log_file.puts("WARNING: Missing TXT file for #{File.basename(yaml_file)}")
    log_file.puts("Expected: #{File.basename(txt_file)}")
    log_file.puts("-" * 50)
    puts "Warning: Missing TXT file for #{File.basename(yaml_file)}"
  end

  def self.write_summary(log_file, total_net_ton, mismatches)
    log_file.puts("SUMMARY")
    log_file.puts("-" * 50)
    log_file.puts("Total Net TON: #{'%.2f' % total_net_ton}")
    log_file.puts("Mismatches: #{mismatches.size}")

    if mismatches.any?
      log_file.puts("Mismatched files:")
      mismatches.each do |mismatch|
        log_file.puts("  #{File.basename(mismatch[:yaml])} - Diff: #{'%.2f' % mismatch[:diff]}")
      end
    end
  end
end

# Usage
yaml_directory = "Processed/TON/YAML"
txt_directory = "CSV_Dumps/TON"
log_file_path = "comparison_log.txt"

TONFormatChecker.compare_files(yaml_directory, txt_directory, log_file_path)
