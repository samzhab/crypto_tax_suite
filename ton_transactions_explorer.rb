require 'httparty'
require 'csv'
require 'json'
require 'time'
require 'byebug'
require 'fileutils'

# Config
wallet_address = 'EQBl3gg6AAdjgjO2ZoNU5Q5EzUIl8XMNZrix8Z5dJmkHUfxI'
# anton_url = "https://anton.tools/api/v0/transactions?address=#{wallet_address}&workchain=0&order=DESC&limit=10000"
anton_url = 'https://public-api.solscan.io/account/transactions?address=5TJDXqWT8EqhT6YtHj6ykDpPUh2iqJfBU2d7wFmQDuA3&limit=100'

def extract_counterparty(tx, type)
  if type == 'IN'
    msg = tx['in_msg']
    return 'Unknown' unless msg

    # Try to get the most readable address format
    if msg.is_a?(Hash)
      msg.dig('src_address', 'base64') || msg.dig('src_address', 'hex') || 'Unknown'
    else
      msg.to_s
    end
  elsif type == 'OUT'
    msg = tx['out_msg']
    return 'Unknown' unless msg

    if msg.is_a?(Array)
      msg.first.dig('dst_address', 'base64') || msg.first.dig('dst_address', 'hex') || 'Unknown'
    elsif msg.is_a?(Hash)
      msg.dig('dst_address', 'base64') || msg.dig('dst_address', 'hex') || 'Unknown'
    else
      msg.to_s
    end
  else
    'N/A'
  end
end

begin
  response = HTTParty.get(anton_url)
  raise "API request failed: #{response.code} - #{response.body}" unless response.success?

  data = JSON.parse(response.body)
  byebug
  transactions = data['results'] || []

  if transactions.any?
    puts "Fetched #{transactions.size} transactions"

    FileUtils.mkdir_p('CSV_Files')

    short_address = "#{wallet_address[0..2]}...#{wallet_address[-4..-1]}"
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    filename = "CSV_Files/ton_transactions_#{short_address}_#{timestamp}.csv"

    CSV.open(filename, 'w') do |csv|
      csv << ['Date (UTC)', 'Tx Hash', 'Type', 'Amount (TON)', 'Fee (TON)', 'Counterparty Address']

      transactions.each do |tx|
        date = tx['created_at'] ? Time.parse(tx['created_at']).utc.strftime("%Y-%m-%d %H:%M:%S") : 'N/A'
        hash = tx['hash'] || 'N/A'
        fee = (tx['total_fees'].to_f / 1_000_000_000).round(9)

        if tx['in_amount'].to_f > 0
          type = 'IN'
          amount = (tx['in_amount'].to_f / 1_000_000_000).round(9)
          counterparty = extract_counterparty(tx, type)
        elsif tx['out_amount'].to_f > 0
          type = 'OUT'
          amount = (tx['out_amount'].to_f / 1_000_000_000).round(9)
          counterparty = extract_counterparty(tx, type)
        else
          type = 'UNKNOWN'
          amount = 0
          counterparty = 'N/A'
        end

        csv << [date, hash, type, amount, fee, counterparty]
      end
    end

    puts "Saved to #{filename}"
  else
    puts "No transactions found or only count available"
    puts "Total transactions count: #{transactions.size}" if transactions.respond_to?(:size)
  end

rescue => e
  puts "Error: #{e.message}"
end
