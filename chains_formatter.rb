require 'csv'
require 'yaml'
require 'fileutils'
require 'date'

class CsvToStandardYaml
  # -----------------------------------------------------------------
  #  HEADER_MAPPINGS – extended for the Tron CSV samples you provided
  # -----------------------------------------------------------------
  HEADER_MAPPINGS = {
    # Date / timestamp columns
    date: [
      'DateTime(UTC)',            # generic
      'DateTime (UTC)',           # generic with space
      'Human Time',               # generic
      'Block Time',               # generic
      'Time (UTC)',               # first CSV sample
      'Time(UTC)'                 # second CSV sample (no space)
    ],

    # Transaction‑type / method columns
    type: [
      'Method',                   # generic
      'Action',                   # generic
      'Type',                     # generic
      'Transaction Type',         # first CSV sample
      'Method Name',              # first CSV sample
      'Method ID'                 # first CSV sample (numeric identifier)
    ],

    # Sender address columns
    sender: [
      'From',                     # generic & both CSVs
      'Sender'                    # generic fallback
    ],

    # Receiver address columns
    receiver: [
      'To',                       # generic & both CSVs
      'Receiver'                  # generic fallback
    ],

    # Amount / token‑quantity columns
    amount: [
      'Value',                    # generic
      'Value_IN(ETH)',            # generic
      'Value_OUT(ETH)',           # generic
      'Value_IN(BNB)',            # generic
      'Value_OUT(BNB)',           # generic
      'Amount',                   # generic & first CSV sample
      'TokenValue',               # generic
      'Amount/TokenID'            # second CSV sample (combined amount / NFT id)
    ],

    # Token identifier columns
    token: [
      'Token',                    # generic
      'TokenSymbol',              # generic
      'TokenName',                # generic
      'ContractAddress',          # generic
      'Token Symbol',             # first CSV sample (space)
      'Token Symbol'              # second CSV sample (same spelling)
    ],

    # Fees – none of the supplied files contain explicit fee columns,
    # but we keep the generic list in case other exports surface them.
    fees: [
      'TxnFee(ETH)', 'TxnFee(USD)', 'TxnFee(BNB)',
      'Fee', 'Txn Fee'
    ],

    # Description / status columns
    description: [
      'Method',       # generic (sometimes used as a description)
      'Action',       # generic
      'Status',       # both CSVs
      'Result'        # both CSVs (SUCCESS / FAIL)
    ]
  }.freeze

  CHAIN_NATIVE_TOKENS = {
    'ETH' => 'ETH',
    'BNB' => 'BNB',
    'TRON' => 'TRX',
    'SOLANA' => 'SOLANA',
    'TON' => 'TON'
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
    total = Dir.glob(File.join(@output_base, '**/YAML/*.yaml')).count
    puts "Processing complete. #{total} YAML files created."
  end

  private

  def process_csv_file(csv_path)
    filename = File.basename(csv_path, '.csv')
    chain, wallet = filename.split('-', 2)
    wallet = wallet.split('-').first rescue 'unknown'
    chain_up = chain.upcase

    output_dir = File.join(@output_base, chain_up, 'YAML')
    FileUtils.mkdir_p(output_dir)

    transactions =
      if chain_up == 'SOLANA' && is_special_sol_format?(csv_path)
        parse_sol_special_csv(csv_path, wallet, chain_up)
      else
        parse_standard_csv(csv_path, chain_up)
      end

    output_data =
      if chain_up == 'TON'
        {
          wallet: wallet,
          transaction_count: transactions.size,
          transactions: transactions.map { |tx| format_ton_style(tx) }
        }
      else
        {
          metadata: {
            source_file: File.basename(csv_path),
            chain: chain_up,
            wallet_address: wallet,
            processed_at: Time.now.utc.iso8601,
            transaction_count: transactions.size
          },
          transactions: transactions
        }
      end

    output_path = File.join(output_dir, "#{filename}.yaml")
    File.write(output_path, output_data.to_yaml)
    puts "Created: #{output_path} (#{transactions.size} transactions)"
  end

  def parse_standard_csv(csv_path, chain)
    transactions = []
    CSV.foreach(csv_path, headers: true) do |row|
      if transaction = extract_transaction(row, chain)
        transactions << transaction
      end
    end
    transactions.sort_by { |t| t[:date] }.reverse
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

  def find_value(row, headers, header_names)
    Array(header_names).each do |header|
      header_key = header.downcase.to_sym
      if headers.key?(header_key)
        value = row[headers[header_key]]
        return value.to_s.strip if value && !value.strip.empty?
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

  def detect_token(row, headers, chain)
    token_headers = HEADER_MAPPINGS[:token]
    token_value = token_headers.lazy.map { |h| find_value(row, headers, h) }.reject(&:nil?).first
    token_value || CHAIN_NATIVE_TOKENS[chain] || chain
  end

  def format_ton_style(tx)
    details = []
    details << tx[:receiver] if tx[:receiver]
    details << tx[:description] if tx[:description]
    if tx[:amount] && tx[:token]
      details << "− #{tx[:amount]} #{tx[:token]}"
    end

    {
      date: tx[:date],
      type: tx[:type],
      details: details
    }
  end

  def is_special_sol_format?(csv_path)
    File.readlines(csv_path).any? { |line| line.include?('Instructions') && line.include?('By') }
  end

  def parse_sol_special_csv(csv_path, wallet, chain)
    lines = File.readlines(csv_path).map(&:strip)
    transactions = []

    current_tx = {}
    price_lines = []
    state = nil

    lines.each_with_index do |line, idx|
      case line
      when /^transfer/i
        current_tx = {
          type: 'TRANSFER',
          token: 'SOLANA',
          sender: nil,
          receiver: nil,
          amount: nil,
          fees: nil,
          description: line.strip
        }
        price_lines = []
        state = :transfer
      when /^\s*[\w.]+\.id$/, /^\s*\w{10,}\.\.\.\w{10,}$/, /^\s*\w{32,}$/
        current_tx[:receiver] ||= line.strip
      when /^\d+\.\d+$/
        price_lines << line.strip.to_f
      when /^\d+\s+(months?|days?)\s+ago/
        current_tx[:date] = extract_date_from_relative_time(line)

        # Only save if we have two prices (amount and fee)
        if price_lines.size >= 2
          current_tx[:amount] = format('%.6f', price_lines[0])
          current_tx[:fees]   = format('%.6f', price_lines[1])
        end

        # Default sender is user's wallet
        current_tx[:sender] = wallet

        transactions << current_tx unless current_tx[:amount].nil?
        current_tx = {}
        price_lines = []
        state = nil
      end
    end

    transactions.compact.select { |tx| tx[:date] && tx[:amount] }.sort_by { |t| t[:date] }.reverse
  end

  def extract_date_from_relative_time(relative)
    today = Date.today

    if relative =~ /(\d+)\s+months?\s+ago/
      today << $1.to_i
    elsif relative =~ /(\d+)\s+days?\s+ago/
      today - $1.to_i
    else
      today
    end.strftime('%Y-%m-%d')
  end
end

# Run the processor
processor = CsvToStandardYaml.new
processor.process_all_files
