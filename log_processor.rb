require 'fileutils'

log_file = 'Processed/TON/Logs/ton_values_report.log'
summary_file = 'Processed/TON/Logs/ton_in_out_summary.log'
tax_detailed_file = 'Processed/TON/Logs/ton_tax_summary.log'
tax_clean_file = 'Processed/TON/Logs/ton_tax_summary_clean.log'

wallet_totals = {}
current_wallet = nil

File.readlines(log_file).each do |line|
  line.strip!

  if line.start_with?(':wallet:')
    current_wallet = line.split(':wallet:').last.strip
    wallet_totals[current_wallet] = {
      in: 0.0,
      out: 0.0,
      samples: []
    }
  elsif line =~ /:transaction_\d+:/
    next unless current_wallet

    label_match = line.match(/:transaction_(\d+):/)
    txn_label = label_match ? ":transaction_#{label_match[1]}:" : ":transaction:"

    # Normalize special characters: Unicode minus (−) and narrow no-break space ( )
    cleaned_line = line.tr('− ', '- ') # Replace Unicode minus and space
    match = cleaned_line.match(/([+-])\s*([\d.,]+)/)
    next unless match

    sign = match[1]
    amount = match[2].gsub(',', '.').to_f

    if sign == '+'
      wallet_totals[current_wallet][:in] += amount
    elsif sign == '-'
      wallet_totals[current_wallet][:out] += amount
    end

    # Store up to 5 sample transactions
    if wallet_totals[current_wallet][:samples].size < 5
      wallet_totals[current_wallet][:samples] << "#{txn_label} #{sign} #{'%.6f' % amount} TON"
    end
  end
end

# === Generate Detailed Wallet Breakdown ===
File.open(summary_file, 'w') do |file|
  wallet_totals.each do |wallet, data|
    file.puts "Wallet: #{wallet}"
    file.puts "  IN: #{'%.6f' % data[:in]} TON"
    file.puts "  OUT: #{'%.6f' % data[:out]} TON"
    file.puts "  Sample Transactions:"
    data[:samples].each { |s| file.puts "    #{s}" }
    file.puts
  end
end

puts "Wallet breakdown written to #{summary_file}"

# === Generate Tax Report With Wallet Breakdown ===
total_in = 0.0
total_out = 0.0

File.open(tax_detailed_file, 'w') do |file|
  wallet_totals.each do |wallet, data|
    total_in += data[:in]
    total_out += data[:out]

    file.puts "Wallet: #{wallet}"
    file.puts "  IN: #{'%.6f' % data[:in]} TON"
    file.puts "  OUT: #{'%.6f' % data[:out]} TON"
    file.puts "  Sample Transactions:"
    data[:samples].each { |s| file.puts "    #{s}" }
    file.puts
  end

  file.puts "=== Total Summary Across All Wallets ==="
  file.puts "  Total IN: #{'%.6f' % total_in} TON"
  file.puts "  Total OUT: #{'%.6f' % total_out} TON"
  file.puts "  Net Position (IN - OUT): #{'%.6f' % (total_in - total_out)} TON"
end

puts "Detailed tax report written to #{tax_detailed_file}"

# === Generate Final CRA-Compliant Summary ===
File.open(tax_clean_file, 'w') do |file|
  file.puts "=== CRA Tax Report Summary for All Wallets ==="
  file.puts "Total IN: #{'%.6f' % total_in} TON"
  file.puts "Total OUT: #{'%.6f' % total_out} TON"
  file.puts "Net Position (IN - OUT): #{'%.6f' % (total_in - total_out)} TON"
end

puts "Final CRA summary written to #{tax_clean_file}"
