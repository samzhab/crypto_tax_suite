require 'csv'
require 'yaml'
require 'fileutils'
require 'date'

class CsvToStandardYaml
  HEADER_MAPPINGS = {
    date: ['DateTime(UTC)', 'DateTime (UTC)', 'Human Time', 'Block Time'],
    type: ['Method', 'Action', 'Type'],
    sender: ['From', 'Sender'],
    receiver: ['To', 'Receiver'],
    amount: ['Value', 'Value_IN(ETH)', 'Value_OUT(ETH)', 'Value_IN(BNB)', 'Value_OUT(BNB)', 'Amount', 'TokenValue'],
    token: ['Token', 'TokenSymbol', 'TokenName', 'ContractAddress'],
    fees: ['TxnFee(ETH)', 'TxnFee(USD)', 'TxnFee(BNB)', 'Fee', 'Txn Fee'],
    description: ['Method', 'Action', 'Status']
  }

  def initialize
    @input_dir = 'CSV_Dumps'
    @output_base = 'Processed'
    FileUtils.mkdir_p(@output_base)
  end

  def process_all_files
    Dir.glob(File.join(@input_dir, '**/*.csv')).each do |csv_path|
      process_csv_file(csv_path)
    end
    puts "Processing complete. #{Dir.glob(File.join(@output_base, '**/*.yaml')).count} YAML files created."
  end

  private

  def process_csv_file(csv_path)
    # Extract chain and wallet from filename (format: CHAIN-wallet-otherinfo.csv)
    filename = File.basename(csv_path, '.csv')
    chain, wallet = filename.split('-', 2)
    wallet = wallet.split('-').first rescue 'unknown'

    output_dir = File.join(@output_base, chain)
    FileUtils.mkdir_p(output_dir)

    transactions = []
    CSV.foreach(csv_path, headers: true) do |row|
      if transaction = extract_transaction(row, chain)
        transactions << transaction
      end
    end

    # Sort transactions by date (newest first)
    sorted_transactions = transactions.sort_by { |t| t[:date] }.reverse

    output_data = {
      metadata: {
        source_file: File.basename(csv_path),
        chain: chain.upcase,
        wallet_address: wallet,
        processed_at: Time.now.utc.iso8601,
        transaction_count: sorted_transactions.size
      },
      transactions: sorted_transactions
    }

    output_path = File.join(output_dir, "#{filename}.yaml")
    File.write(output_path, output_data.to_yaml)
    puts "Created: #{output_path} (#{sorted_transactions.size} transactions)"
  end

  def extract_transaction(row, chain)
    headers = row.headers.each_with_object({}) { |h, hash| hash[h.to_s.downcase.to_sym] = h }

    date = find_value(row, headers, HEADER_MAPPINGS[:date])
    return nil unless date

    amount = find_value(row, headers, HEADER_MAPPINGS[:amount])
    token = detect_token(row, headers, chain)

    {
      date: format_date(date),
      type: find_value(row, headers, HEADER_MAPPINGS[:type]) || 'Transfer',
      sender: find_value(row, headers, HEADER_MAPPINGS[:sender]),
      receiver: find_value(row, headers, HEADER_MAPPINGS[:receiver]),
      amount: format_amount(amount),
      token: token,
      fees: find_value(row, headers, HEADER_MAPPINGS[:fees]),
      description: build_description(row, headers)
    }
  end

  def detect_token(row, headers, chain)
    # Try all token-related headers
    token_headers = HEADER_MAPPINGS[:token]
    token_value = token_headers.lazy.map { |h| find_value(row, headers, h) }.reject(&:nil?).first

    # Fallback to chain-specific token
    token_value || case chain.upcase
                   when 'ETH' then 'ETH'
                   when 'BNB' then 'BNB'
                   when 'TON' then 'TON'
                   else chain.upcase
                   end
  end

  def find_value(row, headers, header_names)
    Array(header_names).each do |header|
      header_key = header.downcase.to_sym
      if headers.key?(header_key) && (value = row[headers[header_key]])
        return value.to_s.strip
      end
    end
    nil
  end

  def format_date(date_str)
    return date_str[0..9] if date_str.match?(/^\d{4}-\d{2}-\d{2}/)

    begin
      DateTime.parse(date_str).strftime('%Y-%m-%d')
    rescue
      date_str[0..9] rescue '0000-00-00'
    end
  end

  def format_amount(amount_str)
    return '0' unless amount_str
    amount_str.gsub(/[^\d\.-]/, '')
  end

  def build_description(row, headers)
    desc = find_value(row, headers, HEADER_MAPPINGS[:description])
    contract = find_value(row, headers, 'ContractAddress')

    [desc, contract].compact.reject(&:empty?).join(' - ')
  end
end

# Run the processor
processor = CsvToStandardYaml.new
processor.process_all_files
