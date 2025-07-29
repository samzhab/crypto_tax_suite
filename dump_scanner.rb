require 'csv'

# Configuration
CSV_DUMPS_DIR = 'CSV_Dumps'
OUTPUT_REPORT = 'wallet_analysis_report.txt'
HEX_REGEX = /[a-fA-F0-9]{40,}\b/  # Standard Ethereum-style addresses
COMMON_ADDRESS_COLUMNS = ['from', 'to', 'address', 'wallet', 'sender', 'receiver', 'account']

def scan_files
  all_wallets = Hash.new(0)
  file_reports = []
  wallet_file_map = Hash.new { |h, k| h[k] = Set.new }
  wallet_transaction_counts = Hash.new(0)

  Dir.glob(File.join(CSV_DUMPS_DIR, '*.csv')).each do |file_path|
    file_wallets = Hash.new(0)
    file_name = File.basename(file_path)
    transactions_in_file = 0

    begin
      CSV.foreach(file_path, headers: true) do |row|
        transactions_in_file += 1
        found_in_row = Set.new

        # Check common address columns first
        row.headers.each do |header|
          next unless COMMON_ADDRESS_COLUMNS.any? { |kw| header.downcase.include?(kw) }

          if row[header] && row[header].match(HEX_REGEX)
            wallet = row[header].match(HEX_REGEX)[0]
            file_wallets[wallet] += 1
            all_wallets[wallet] += 1
            found_in_row.add(wallet)
            wallet_transaction_counts[wallet] += 1
          end
        end

        # Fallback: Scan all columns if no addresses found in common columns
        if found_in_row.empty?
          row.to_s.scan(HEX_REGEX).each do |wallet|
            file_wallets[wallet] += 1
            all_wallets[wallet] += 1
            wallet_transaction_counts[wallet] += 1
          end
        end
      end

      # Record which files each wallet appears in
      file_wallets.each_key { |wallet| wallet_file_map[wallet].add(file_name) }

      file_reports << {
        filename: file_name,
        transactions: transactions_in_file,
        total_wallet_occurrences: file_wallets.values.sum,
        unique_wallets: file_wallets.size,
        wallets: file_wallets
      }
    rescue => e
      file_reports << {
        filename: file_name,
        error: "Failed to process: #{e.message}"
      }
    end
  end

  [file_reports, all_wallets, wallet_file_map, wallet_transaction_counts]
end

def generate_report(file_reports, all_wallets, wallet_file_map, wallet_transaction_counts)
  report = []

  # Individual file reports
  report << "=== INDIVIDUAL FILE REPORTS ==="
  file_reports.each do |file|
    report << "\nFile: #{file[:filename]}"
    if file[:error]
      report << "  ERROR: #{file[:error]}"
    else
      report << "  Transactions: #{file[:transactions]}"
      report << "  Total wallet occurrences: #{file[:total_wallet_occurrences]}"
      report << "  Unique wallets: #{file[:unique_wallets]}"

      if file[:unique_wallets] > 0
        report << "  Top wallets in this file:"
        file[:wallets].sort_by { |k,v| -v }.first(5).each do |wallet, count|
          report << "    #{wallet} (in #{wallet_file_map[wallet].size} files, #{wallet_transaction_counts[wallet]} total txns): #{count} occurrence(s)"
        end
      end
    end
  end

  # Summary report
  report << "\n\n=== SUMMARY REPORT ==="
  report << "Total files scanned: #{file_reports.size}"
  report << "Total transactions processed: #{file_reports.sum { |f| f[:transactions] || 0 }}"
  report << "Total wallet occurrences across all files: #{all_wallets.values.sum}"
  report << "Total unique wallets found: #{all_wallets.size}"

  if all_wallets.any?
    # Top wallets by occurrence
    report << "\nTop 20 wallets by occurrence:"
    all_wallets.sort_by { |k,v| -v }.first(20).each do |wallet, count|
      report << "  #{wallet}: #{count} occurrences across #{wallet_file_map[wallet].size} files (#{wallet_transaction_counts[wallet]} transactions)"
    end

    # Wallets appearing in multiple files
    report << "\nWallets appearing in multiple files:"
    multi_file_wallets = wallet_file_map.select { |k, v| v.size > 1 }
    if multi_file_wallets.any?
      multi_file_wallets.sort_by { |k, v| -v.size }.each do |wallet, files|
        report << "  #{wallet}: appears in #{files.size} files (#{wallet_transaction_counts[wallet]} transactions)"
      end
    else
      report << "  None found"
    end

    # High activity wallets
    report << "\nHigh activity wallets (10+ transactions):"
    high_activity = wallet_transaction_counts.select { |k, v| v >= 10 }
    if high_activity.any?
      high_activity.sort_by { |k, v| -v }.each do |wallet, count|
        report << "  #{wallet}: #{count} transactions across #{wallet_file_map[wallet].size} files"
      end
    else
      report << "  None found"
    end
  end

  # Write to file
  File.write(OUTPUT_REPORT, report.join("\n"))
  puts "Advanced wallet analysis report generated: #{OUTPUT_REPORT}"
end

# Main execution
if Dir.exist?(CSV_DUMPS_DIR)
  file_reports, all_wallets, wallet_file_map, wallet_transaction_counts = scan_files
  generate_report(file_reports, all_wallets, wallet_file_map, wallet_transaction_counts)
else
  puts "Error: Directory '#{CSV_DUMPS_DIR}' not found."
end
