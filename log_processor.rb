require 'yaml'
require 'byebug'

# Step 1: Look for the specific file
log_file = File.join("Processed/TON/Logs", "ton_values_report.log")
raise "File 'ton_values_report.log' not found in Processed/TON/Logs." unless File.exist?(log_file)

# Step 2: Prepare to extract data
wallet_data = {}
current_wallet = nil

File.foreach(log_file) do |line|
  line.strip!

  if line.start_with?(':wallet:')
    current_wallet = line.split(':wallet:').last.strip
    wallet_data[current_wallet] ||= { total: 0.0, transaction_count: 0 }
  elsif line =~ /:transaction_\d+:/
    if current_wallet
      match = line.match(/:transaction_\d+:\s*([−\+])\u202F*([\d\.]+)\s*TON/)
      if match
        sign = match[1]
        amount = match[2].to_f
        amount *= -1 if sign == '−'  # Handle Unicode minus
        wallet_data[current_wallet][:total] += amount
        wallet_data[current_wallet][:transaction_count] += 1
      end
    end
  end
end

# Output file
output_file = File.join("Processed/TON/Logs", "wallet_totals.log")

File.open(output_file, "w") do |f|
  wallet_data.each do |wallet, data|
    sign = data[:total].negative? ? '−' : '+'  # Preserve Unicode minus
    formatted_total = "#{sign}\u202F#{data[:total].abs.round(8)} TON"
    f.puts ":wallet: #{wallet}"
    f.puts ":total: #{formatted_total}"
    f.puts ":transaction_count: #{data[:transaction_count]}"
    f.puts
  end
end

puts "✅ Wallet totals and transaction counts saved to #{output_file}"
