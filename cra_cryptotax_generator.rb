require 'csv'
require 'time'
require 'yaml'
require 'date'

# Configuration
FMV_FILE = 'historical_fmv_ton_cad.yaml'
CSV_FOLDER = 'CRA_Reports'
LOG_FOLDER = 'logs'
INPUT_FOLDER = 'CSV_Files'

# Create output directories
Dir.mkdir(CSV_FOLDER) unless Dir.exist?(CSV_FOLDER)
Dir.mkdir(LOG_FOLDER) unless Dir.exist?(LOG_FOLDER)

def log_activity(message)
  timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  log_entry = "[#{timestamp}] #{message}\n"
  File.write("#{LOG_FOLDER}/processing.log", log_entry, mode: 'a')
  puts message
end

def load_fmv_data
  if File.exist?(FMV_FILE)
    begin
      data = YAML.safe_load(File.read(FMV_FILE), permitted_classes: [Date])
      # Convert all keys to Date objects for consistent lookup
      data.transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k }
    rescue => e
      log_activity("ERROR loading FMV data: #{e.message}")
      {}
    end
  else
    log_activity("WARNING: FMV file #{FMV_FILE} not found")
    {}
  end
end

def get_cad_value(date_str, amount, fmv_data)
  begin
    date = Date.parse(date_str)
    fmv = fmv_data[date]
    fmv ? (amount.to_f * fmv).round(4) : 'N/A'
  rescue => e
    log_activity("WARNING: Couldn't calculate CAD for #{date_str}: #{e.message}")
    'N/A'
  end
end

def generate_transaction_csv(wallet_id, year, transactions, fmv_data)
  timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
  output_file = "#{CSV_FOLDER}/cra_fmv_#{wallet_id}_#{year}_#{timestamp}.csv"

  CSV.open(output_file, 'w') do |csv|
    csv << ['Date (UTC)', 'Tx Hash', 'Type', 'Amount (TON)', 'Fee (TON)', 'Counterparty Address', 'CAD Value']

    transactions.each do |tx|
      cad_value = get_cad_value(tx['Date (UTC)'], tx['Amount (TON)'], fmv_data)

      csv << [
        tx['Date (UTC)'],
        tx['Tx Hash'],
        tx['Type'],
        tx['Amount (TON)'],
        tx['Fee (TON)'],
        tx['Counterparty Address'],
        cad_value
      ]
    end
  end

  output_file
end

def generate_cra_tax_report(wallet_id, year, transactions, fmv_data)
  report_data = {
    tax_year: year,
    wallet_id: wallet_id,
    generated_at: Time.now.iso8601,
    transactions: {
      count: transactions.size,
      incoming_ton: transactions.sum { |t| t['Type'] == 'IN' ? t['Amount (TON)'].to_f : 0 }.round(9),
      outgoing_ton: transactions.sum { |t| t['Type'] == 'OUT' ? t['Amount (TON)'].to_f : 0 }.round(9),
      fees_ton: transactions.sum { |t| t['Fee (TON)'].to_f }.round(9)
    },
    cad_values: {
      total_incoming_cad: transactions.sum { |t|
        t['Type'] == 'IN' ? get_cad_value(t['Date (UTC)'], t['Amount (TON)'], fmv_data).to_f : 0
      }.round(2),
      total_outgoing_cad: transactions.sum { |t|
        t['Type'] == 'OUT' ? get_cad_value(t['Date (UTC)'], t['Amount (TON)'], fmv_data).to_f : 0
      }.round(2),
      average_rate: transactions.sum { |t|
        date = begin Date.parse(t['Date (UTC)']) rescue nil end
        date && fmv_data[date] ? fmv_data[date] : 0
      }.to_f / transactions.size
    },
    capital_gains: calculate_capital_gains(transactions, fmv_data)
  }

  report_file = "#{CSV_FOLDER}/cra_tax_report_#{wallet_id}_#{year}_#{Time.now.strftime('%Y%m%d')}.csv"

  # Save as CSV
  CSV.open(report_file, 'w') do |csv|
    csv << ['Category', 'Value', 'Currency']
    report_data.each do |category, values|
      if values.is_a?(Hash)
        values.each { |k, v| csv << [k.to_s.gsub('_', ' ').capitalize, v, k.to_s.end_with?('cad') ? 'CAD' : 'TON'] }
      else
        csv << [category.to_s.gsub('_', ' ').capitalize, values, '']
      end
    end
  end

  report_file
end

def calculate_capital_gains(transactions, fmv_data)
  acb = 0.0
  proceeds = 0.0
  gains = 0.0

  transactions.each do |tx|
    date = begin Date.parse(tx['Date (UTC)']) rescue nil end
    next unless date

    amount = tx['Amount (TON)'].to_f
    rate = fmv_data[date] || 0
    cad_value = amount * rate

    if tx['Type'] == 'IN'
      acb += cad_value
    elsif tx['Type'] == 'OUT'
      proceeds += cad_value
      cost = amount * (acb / (amount.abs + 1e-9)) # Prevent division by zero
      gains += (cad_value - cost)
      acb -= cost
    end
  end

  {
    total_proceeds: proceeds.round(2),
    total_acb: acb.round(2),
    net_gain: gains.round(2)
  }
end

# Main execution
log_activity("Starting TON tax report generation")
fmv_data = load_fmv_data

# Process all wallets
Dir.glob("#{INPUT_FOLDER}/ton_transactions_*.csv").group_by { |f|
  File.basename(f).split('_')[2..-3].join('_') rescue 'unknown'
}.each do |wallet_id, files|
  latest_file = files.max_by { |f| File.mtime(f) }
  log_activity("Processing wallet: #{wallet_id} (file: #{File.basename(latest_file)})")

  CSV.read(latest_file, headers: true).group_by { |tx|
    (Time.parse(tx['Date (UTC)']) rescue Time.now).year
  }.each do |year, transactions|
    # Generate full transaction CSV with CAD values
    csv_file = generate_transaction_csv(wallet_id, year, transactions, fmv_data)
    log_activity("↳ Saved transaction records: #{File.basename(csv_file)}")

    # Generate CRA tax report
    report_file = generate_cra_tax_report(wallet_id, year, transactions, fmv_data)
    log_activity("↳ Generated CRA tax report: #{File.basename(report_file)}")

    # Print summary to console
    puts "\n#{'=' * 50}"
    puts "TAX YEAR #{year} SUMMARY - #{wallet_id}".center(50)
    puts "#{transactions.size} transactions processed".center(50)
    puts "CAD values calculated using #{fmv_data.size} exchange rates".center(50)
    puts '=' * 50
  end
end

log_activity("Processing complete")
puts "\n#{'=' * 50}"
puts "REPORT GENERATION COMPLETE".center(50)
puts "#{Dir.glob("#{CSV_FOLDER}/cra_fmv_*.csv").size} transaction files".center(50)
puts "#{Dir.glob("#{CSV_FOLDER}/cra_tax_report_*.csv").size} tax reports".center(50)
puts '=' * 50
