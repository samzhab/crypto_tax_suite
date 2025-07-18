require 'date'
require 'yaml'
require 'fileutils'

class TonProcessor
  def initialize
    @input_dir = 'CSV_Dumps/TON'
    @output_base = 'Processed/TON'
    @yaml_dir = "#{@output_base}/YAML"
    @log_dir = "#{@output_base}/Logs"

    FileUtils.mkdir_p(@yaml_dir)
    FileUtils.mkdir_p(@log_dir)
  end

  def process_files
    total_files = 0
    total_transactions = 0
    errors = []

    Dir.glob("#{@input_dir}/TON_*.txt").each do |file_path|
      wallet = File.basename(file_path, '.txt').sub('TON_', '')

      begin
        transactions = parse_file(file_path)
        save_yaml(wallet, transactions)
        save_log(wallet, transactions.size)

        total_files += 1
        total_transactions += transactions.size
        puts "Processed #{wallet}: #{transactions.size} transactions"
      rescue => e
        errors << "Failed to process #{wallet}: #{e.message}"
        puts "Error processing #{wallet}"
      end
    end

    save_summary(total_files, total_transactions, errors)
  end

  private

  def parse_file(file_path)
    transactions = []
    current_transaction = []

    File.foreach(file_path) do |line|
      line = line.strip
      next if line.empty?

      if date_line?(line)
        transactions << process_transaction(current_transaction) if current_transaction.any?
        current_transaction = [line]
      else
        current_transaction << line
      end
    end
    transactions << process_transaction(current_transaction) if current_transaction.any?
    transactions
  end

  def process_transaction(lines)
    {
      date: format_date(lines.first),
      type: lines[1],
      details: lines[2..-1]
    }
  end

  def format_date(date_str)
    return date_str unless date_line?(date_str)

    parts = date_str.split
    day = parts[0]
    month = parts[1]
    year = parts[2] =~ /\d{4}/ ? parts[2] : '2025' # Assuming current year if not present

    Date.parse("#{day} #{month} #{year}").strftime('%Y-%m-%d')
  rescue
    date_str
  end

  def date_line?(line)
    line.match?(/^\d{1,2} [A-Za-z]{3}/)
  end

  def save_yaml(wallet, transactions)
    data = {
      wallet: wallet,
      transaction_count: transactions.size,
      transactions: transactions
    }

    File.write("#{@yaml_dir}/#{wallet}.yaml", data.to_yaml)
  end

  def save_log(wallet, count)
    log_content = [
      "Wallet: #{wallet}",
      "Processed at: #{Time.now}",
      "Transactions: #{count}",
      "Status: Success"
    ].join("\n")

    File.write("#{@log_dir}/#{wallet}.log", log_content)
  end

  def save_summary(files, transactions, errors)
    summary_content = [
      "Summary Report:",
      "Total Files Processed: #{files}",
      "Total Transactions: #{transactions}"
    ]

    if errors.any?
      summary_content << "Errors:"
      errors.each { |error| summary_content << "- #{error}" }
    else
      summary_content << "Status: All files processed successfully."
    end

    File.write("#{@output_base}/summary.log", summary_content.join("\n"))
  end
end

processor = TonProcessor.new
processor.process_files
