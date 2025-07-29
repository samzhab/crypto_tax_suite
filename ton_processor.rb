require 'csv'
require 'date'
require 'fileutils'

class TonTransactionProcessor
  def initialize
    @input_folder = 'TON_Viewer_Dumps'
    @output_csv_folder = 'TON_Viewer_Reports/CSVs'
    @output_reports_folder = 'TON_Viewer_Reports/Reports'
    @all_transactions = []
    @token_balances = Hash.new(0)
    @transaction_counts = Hash.new(0)
    @years_processed = Set.new

    create_folders
  end

  def create_folders
    FileUtils.mkdir_p(@output_csv_folder)
    FileUtils.mkdir_p(@output_reports_folder)
  end

  def process_all_files
    Dir.glob(File.join(@input_folder, '*.txt')).each do |file_path|
      process_file(file_path)
    end

    generate_summary_reports
    display_summary
  end

  def process_file(file_path)
    filename = File.basename(file_path, '.txt')
    puts "Processing file: #{filename}"

    transactions = []
    current_transaction = nil
    current_date = nil

    File.readlines(file_path).each do |line|
      line.strip!
      next if line.empty? || line.include?('Failed') || line.include?('failed')

      # Check for new date (start of new transaction)
      if line =~ /^\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{2}:\d{2}/ ||
         line =~ /^\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4}/
        # Save previous transaction if exists
        if current_transaction
          transactions << current_transaction
          @all_transactions << current_transaction.merge(filename: filename)
        end

        # Parse date and create new transaction
        date_str = line.split.first(3).join(' ')
        current_date = parse_date(date_str)
        @years_processed << current_date.year

        current_transaction = {
          date: current_date,
          action: nil,
          counterparty: nil,
          memo: nil,
          values: [],
          filename: filename
        }
      elsif current_date && line =~ /^(Sent TON|Received TON|Send token|Received token|Called contract|Swap tokens|Burn token|Mint token|Deposit stake|Stake withdraw|Withdrawal request|Send NFT|Received NFT)/
        # Extract action
        action = line.split.first(2).join(' ').downcase

        # For multi-part transactions, we'll update the action based on the final result
        current_transaction[:action] ||= action || 'unknown'
        # Extract counterparty and memo
        parts = line.split('  ').map(&:strip).reject(&:empty?)
        counterparty = parts[1] || '-'
        memo = parts[2..-1].join(' | ') rescue nil

        # Extract token amount if present
        if line =~ /([−\-+])\s*([\d,]+\.?\d*)\s+([A-Za-z0-9₮\-]+)/
          sign = $1
          amount = $2.gsub(',', '').to_f
          token = $3

          # Determine direction and adjust amount
          direction = sign == '+' ? :in : :out
          adjusted_amount = direction == :in ? amount : -amount

          current_transaction[:values] << { token: token, amount: adjusted_amount }
          @token_balances[token] += adjusted_amount
        end

        # For NFT transactions
        if action.include?('nft')
          current_transaction[:action] = action
          current_transaction[:counterparty] = counterparty
          current_transaction[:memo] = memo
          current_transaction[:values] = [] # Clear values for NFT
        end

        # For swap transactions
        if action == 'swap tokens'
          current_transaction[:action] = 'swap'
          current_transaction[:counterparty] = counterparty
        end
      end
    end

    # Add the last transaction if exists
    if current_transaction
      transactions << current_transaction
      @all_transactions << current_transaction.merge(filename: filename)
    end

    # Generate CSV for this file
    generate_csv(filename, transactions)
  end

  def parse_date(date_str)
    # Handle dates with year and without year
    if date_str =~ /(\d{1,2}) (\w{3}) (\d{4})/
      day = $1.to_i
      month = Date::ABBR_MONTHNAMES.index($2)
      year = $3.to_i
      Date.new(year, month, day)
    else
      # Assume current year for dates without year
      day = date_str.split.first.to_i
      month = Date::ABBR_MONTHNAMES.index(date_str.split[1])
      year = Date.today.year
      Date.new(year, month, day)
    end
  rescue
    Date.today # Fallback for parsing errors
  end

  def generate_csv(filename, transactions)
    csv_path = File.join(@output_csv_folder, "#{filename}.csv")

    CSV.open(csv_path, 'w') do |csv|
      csv << ['date', 'wallet', 'action', 'counterparty', 'memo', 'values']

      transactions.each do |tx|
        # Skip failed transactions
        next if tx[:action].to_s.downcase.include?('fail')

        # Calculate net values for the transaction
        net_values = calculate_net_values(tx[:values])

        # Format values string
        values_str = net_values.map { |v| "#{v[:amount].abs} #{v[:token]}" }.join(' | ')

        # Count transaction types
        @transaction_counts[tx[:action]] ||= 0
        @transaction_counts[tx[:action] || 'unknown'] += 1
        csv << [
          tx[:date].to_s,
          filename,
          tx[:action],
          tx[:counterparty],
          tx[:memo],
          values_str
        ]
      end
    end
  end

  def calculate_net_values(values)
    # Group by token and sum amounts
    net_values = Hash.new(0)
    token_names = {}

    values.each do |v|
      net_values[v[:token]] += v[:amount]
      token_names[v[:token]] = v[:token]
    end

    # Convert back to array of hashes
    net_values.map { |token, amount| { token: token_names[token], amount: amount } }
  end

  def generate_summary_reports
    @years_processed.each do |year|
      generate_year_report(year)
    end
    generate_combined_report
  end

  def generate_year_report(year)
    year_transactions = @all_transactions.select { |tx| tx[:date].year == year }
    return if year_transactions.empty?

    report_path = File.join(@output_reports_folder, "TON_Tax_Report_#{year}.txt")

    File.open(report_path, 'w') do |file|
      file.puts "TON Wallet Tax Report #{year}"
      file.puts "Generated on: #{Date.today}"
      file.puts "=" * 80
      file.puts

      # Transaction statistics
      file.puts "1. Transaction Statistics"
      file.puts "-" * 40
      file.puts "Total transactions: #{year_transactions.size}"

      # Transaction type counts
      type_counts = Hash.new(0)
      year_transactions.each { |tx| type_counts[tx[:action] || "unknown"] += 1 }
      file.puts "\nTransaction types:"
      type_counts.each do |type, count|
      file.puts "#{(type || 'unknown').capitalize}: #{count}"      end

      # Rest of the method remains the same...
    end
  end

  def generate_combined_report
    report_path = File.join(@output_reports_folder, "Combined_TON_Tax_Report.txt")

    File.open(report_path, 'w') do |file|
      file.puts "Combined TON Wallet Tax Report"
      file.puts "Generated on: #{Date.today}"
      file.puts "=" * 80
      file.puts

      # Overall statistics
      file.puts "1. Overall Statistics"
      file.puts "-" * 40
      file.puts "Total wallets processed: #{Dir.glob(File.join(@input_folder, '*.txt')).count}"
      file.puts "Total transactions processed: #{@all_transactions.size}"

      # Combined TON movements
      ton_movements = calculate_ton_movements(@all_transactions)
      file.puts "\n2. Combined TON Transactions"
      file.puts "-" * 40
      file.puts "Total TON sent: #{ton_movements[:sent].abs}"
      file.puts "Total TON received: #{ton_movements[:received]}"
      file.puts "Net TON movement: #{ton_movements[:net]}"

      # Combined Jetton holdings
      file.puts "\n3. Combined Jetton Holdings"
      file.puts "-" * 40
      @token_balances.each do |jetton, balance|
        next if jetton.downcase == 'ton' # Skip TON as we have separate section for it
        file.puts "#{jetton}: #{balance}"
      end
    end
  end

  def calculate_ton_movements(transactions)
    sent = 0
    received = 0

    transactions.each do |tx|
      tx[:values].each do |value|
        if value[:token].downcase == 'ton'
          if value[:amount] < 0
            sent += value[:amount].abs
          else
            received += value[:amount]
          end
        end
      end
    end

    { sent: sent, received: received, net: received - sent }
  end

  def calculate_jetton_balances(transactions)
    balances = Hash.new(0)

    transactions.each do |tx|
      tx[:values].each do |value|
        balances[value[:token]] += value[:amount] unless value[:token].downcase == 'ton'
      end
    end

    balances
  end

  def display_summary
    puts "\nProcessing Summary:"
    puts "-" * 40
    puts "Total wallets processed: #{Dir.glob(File.join(@input_folder, '*.txt')).count}"
    puts "Total transactions processed: #{@all_transactions.size}"
    puts "Years processed: #{@years_processed.to_a.sort.join(', ')}"

    puts "\nTransaction Type Counts:"
    puts "-" * 40
    @transaction_counts.each do |type, count|
      puts "#{type.capitalize}: #{count}"
    end

    puts "\nReports generated in:"
    puts "-" * 40
    puts "CSVs: #{@output_csv_folder}"
    puts "Reports: #{@output_reports_folder}"
  end
end

# Run the processor
processor = TonTransactionProcessor.new
processor.process_all_files
