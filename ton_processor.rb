Below is the complete, ready‑to‑run ton_processor.rb.
All the original functionality is kept (parsing the raw txt dumps, building per‑wallet CSVs, creating yearly & combined tax reports), and the new requirements are added:

    require 'csv', require 'date', require 'fileutils' – already at the top.
    Hard‑coded exception list (the SamaelLabs wallets you asked to ignore).
    Aggregation of addresses that appear ≥ 5 times (excluding the exceptions).
    Three output artefacts in one pass:
        report.yaml – detailed per‑address data (count, first/last date, inferred category).
        report.csv – flat CSV version of the same data.
        summary.txt – quick‑look insights (top active addresses, category distribution, overall date range).
    The existing per‑wallet CSVs and tax reports remain untouched.

Just drop the file into the same folder as your TON_Viewer_Dumps directory and run it with ruby ton_processor.rb.

#!/usr/bin/env ruby
# frozen_string_literal: true

# ----------------------------------------------------------------------
#  ton_processor.rb
#  ---------------------------------------------------------------
#  What this script does (single execution):
#    1️⃣  Reads every *.txt file in TON_Viewer_Dumps/
#    2️⃣  Parses each transaction line (date, action, counter‑party, amounts)
#    3️⃣  Skips the hard‑coded SamaelLabs exception addresses.
#    4️⃣  Builds per‑wallet CSV files (already part of the original code).
#    5️⃣  Generates yearly tax‑reports and a combined tax‑report.
#    6️⃣  Produces three additional artefacts that answer the
#        “addresses with ≥5 transactions (excluding exceptions)” request:
#          • report.yaml   – rich per‑address data
#          • report.csv    – flat CSV version of the same data
#          • summary.txt   – concise insights (top 5, category breakdown, date range)
#  --------------------------------------------------------------------

require 'csv'
require 'date'
require 'fileutils'
require 'set'
require 'json'
require 'yaml'

# ----------------------------------------------------------------------
# 1️⃣  Exception list – SamaelLabs owned addresses (strike‑through list)
# ----------------------------------------------------------------------
EXCEPTIONS = Set.new(%w[
  UQBsit-hlJ4tgPVuVlVxSg6MmUDPs0cH_inLVu7_80_jJ9EQ
  UQAnlbI8CtPghlvSOSdGJgPZsCqlG1ku30O6ROIITZKCGt0U
  UQAt0U6sMDFB5C0bYEn3gtJPscd_PJyrkYH0kiYTEOBFsaod
  UQAJPEju0zLAz2LS1tD4KeNUyjfLnKlB9QSLkE8wY-fmEch
  UQBNtOqJ-K5Z7D38sWv5uSHLdUr8Lriv4A_CIa03yS-piRaS
  UQApxB9mmS09P1OxDJUQKLnZL9dNhVmD4ojFeS7UxtdY_MMs
  UQDFGQuasyORl_-KnkvfmI922aixy9bnRy54bgbh9Aj8Kpog
  UQA9rj1zu2Gu8zKmEcL4DG4OjYXVWxajJCX_H5nqltzuc3EQ
  UQCF7eU1AaHJ06AjtSg96FKl-qUWc_nMq8ZIt5sxI9cmjvF3
  TFRZngPXpFXqJkrW9RqpoBmMNwtYcAvtL1
  UQCIPL9JoBB3HejQjjzxeesxcL2ddT_UoEE40pzeCTKRveJ9
  UQA-FcQqFuXFAzF-4QW_QR6JPXoXaf8DyiPgGZ9l10kzf2Uf
  UQCXG_Kq-zDokPLsRQWDsm4j8w2HfVkWYP4HbpG2pnXbHsi8
  UQBo9pEYNUQGVx-2B5E5zdGa1RQihhIJJ6OY4-RtqZnJjtnT
  UQDDsEii7dG7QZdMucPJLhu8_PMrlvccU5EmQWS28ynOOvky
  UQBmskEdlt1pXjDdx-18F-4cirBxhC8NxD02K0BddIHkNLAE
  UQC0iHyWPK_AIYl6UNb8lUvW0oacIImN7Gh9itfrv4EKACms
  UQB6uJBOSRyaqwDbq1BZPi6h0voU0-ozG6nXRz32Yna8r-4n
  UQDX54vAMelwQBFoTzr5mYueNqb6b11e0u6GUQhbXarcpPrO
  UQAMxOyx5WX5dgZz1ncvUKnFeXkFsistQIECIRp2v77mW7am
  UQD6cLQP7LG1wQTJO73SYMu6goWXHwkGfWxrhZbx6q7YeOqf
]).freeze

# ----------------------------------------------------------------------
# 2️⃣  Very light categorisation – helps the summary report
# ----------------------------------------------------------------------
def infer_category(address)
  case address
  when /dedust/i               then :dex_dedust
  when /stonfi/i               then :dex_stonfi
  when /official[-_]nft\.ton/i then :nft_marketplace
  when /sphynxmeme\.ton/i      then :nft_collection
  when /^UQ[A-Z]{2}/          then :user_wallet
  else                             :other
  end
end

# ----------------------------------------------------------------------
# 3️⃣  Main processor class (original logic + new reporting)
# ----------------------------------------------------------------------
class TonTransactionProcessor
  def initialize
    @input_folder          = 'TON_Viewer_Dumps'
    @output_csv_folder     = 'TON_Viewer_Reports/CSVs'
    @output_reports_folder = 'TON_Viewer_Reports/Reports'

    @all_transactions      = []                 # every parsed transaction (hash)
    @token_balances        = Hash.new(0)        # jetton totals across all wallets
    @transaction_counts    = Hash.new(0)        # action => count
    @years_processed       = Set.new

    # New containers for the “≥5 tx” analysis
    @address_stats         = Hash.new { |h, k| h[k] = { count: 0, first_seen: nil, last_seen: nil } }

    create_folders
  end

  # --------------------------------------------------------------
  def create_folders
    FileUtils.mkdir_p(@output_csv_folder)
    FileUtils.mkdir_p(@output_reports_folder)
  end

  # --------------------------------------------------------------
  def process_all_files
    Dir.glob(File.join(@input_folder, '*.txt')).each do |file_path|
      process_file(file_path)
    end

    generate_summary_reports
    display_summary
  end

  # --------------------------------------------------------------
  def process_file(file_path)
    filename = File.basename(file_path, '.txt')
    puts "Processing file: #{filename}"

    transactions = []
    current_transaction = nil
    current_date = nil

    File.readlines(file_path).each do |raw_line|
      line = raw_line.strip
      next if line.empty? || line.include?('Failed') || line.include?('failed')

      # ------------------------------------------------------------------
      # Detect start of a new transaction (date line)
      # ------------------------------------------------------------------
      if line =~ /^\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{2}:\d{2}/ ||
         line =~ /^\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4}/
        # Save previous transaction (if any)
        if current_transaction
          transactions << current_transaction
          @all_transactions << current_transaction.merge(filename: filename)
        end

        # Parse the date string
        date_str = line.split.first(3).join(' ')
        current_date = parse_date(date_str)
        @years_processed << current_date.year

        # Initialise a fresh transaction hash
        current_transaction = {
          date:        current_date,
          action:      nil,
          counterparty: nil,
          memo:        nil,
          values:      [],   # array of { token:, amount: }
          filename:    filename
        }
        next
      end

      # ------------------------------------------------------------------
      # Transaction detail line (Sent/Received …, Swap, NFT, etc.)
      # ------------------------------------------------------------------
      next unless current_date && line =~ /^(Sent TON|Received TON|Send token|Received token|Called contract|Swap tokens|Burn token|Mint token|Deposit stake|Stake withdraw|Withdrawal request|Send NFT|Received NFT)/

      # Normalise the action (lower‑case, keep “swap” as a single word)
      raw_action = line.split.first(2).join(' ').downcase
      action = case raw_action
               when 'swap tokens' then 'swap'
               else raw_action
               end
      current_transaction[:action] ||= action

      # Split on double spaces to pull out counter‑party and memo (if present)
      parts = line.split('  ').map(&:strip).reject(&:empty?)
      counterparty = parts[1] || '-'
      memo = parts[2..].join(' | ') rescue nil
      current_transaction[:counterparty] = counterparty
      current_transaction[:memo] = memo

      # ------------------------------------------------------------------
      # Extract amount + token (e.g. "+ 12.34 TON", "- 5 000 USDT")
      # ------------------------------------------------------------------
      if line =~ /([−\-+])\s*([\d,]+\.?\d*)\s+([A-Za-z0-9₮\-\_]+)/   # token may contain ₮ or dash
        sign = Regexp.last_match(1)
        amount = Regexp.last_match(2).gsub(',', '').to_f
        token = Regexp.last_match(3)

        direction = sign == '+' ? :in : :out
        adjusted_amount = direction == :in ? amount : -amount

        current_transaction[:values] << { token: token, amount: adjusted_amount }
        @token_balances[token] += adjusted_amount
      end

      # ------------------------------------------------------------------
      # Update global address statistics (used for the ≥5‑tx report)
      # ------------------------------------------------------------------
      # Only consider the *counter‑party* address for the stats – the wallet
      # that generated the file (filename) is already captured elsewhere.
      unless EXCEPTIONS.include?(counterparty)
        stats = @address_stats[counterparty]
        stats[:count] += 1
        stats[:first_seen] = current_date if stats[:first_seen].nil? || current_date < stats[:first_seen]
        stats[:last_seen]  = current_date if stats[:last_seen].nil?  || current_date > stats[:last_seen]
      end
    end

    # ------------------------------------------------------------------
    # Flush the very last transaction of the file
    # ------------------------------------------------------------------
    if current_transaction
      transactions << current_transaction
      @all_transactions << current_transaction.merge(filename: filename)
    end

    # ------------------------------------------------------------------
    # Write per‑wallet CSV (original behaviour)
    # ------------------------------------------------------------------
    generate_csv(filename, transactions)
  end

  # --------------------------------------------------------------
  # Parse dates that may or may not contain a year
  # --------------------------------------------------------------
  def parse_date(date_str)
    # With explicit year (e.g. "12 Sep 2024")
    if date_str =~ /(\d{1,2}) (\w{3}) (\d{4})/
      day   = Regexp.last_match(1).to_i
      month = Date::ABBR_MONTHNAMES.index(Regexp.last_match(2))
      year  = Regexp.last_match(3).to_i
      Date.new(year, month, day)
    else
      # Without year – assume current year
      day   = date_str.split.first.to_i
      month = Date::ABBR_MONTHNAMES.index(date_str.split[1])
      year  = Date.today.year
      Date.new(year, month, day)
    end
  rescue StandardError
    Date.today
  end

  # --------------------------------------------------------------
  # Write the per‑wallet CSV (unchanged apart from a tiny refactor)
  # --------------------------------------------------------------
  def generate_csv(filename, transactions)
    csv_path = File.join(@output_csv_folder, "#{filename}.csv")
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[date wallet action counterparty memo values]

      transactions.each do |tx|
        next if tx[:action].to_s.downcase.include?('fail')

        net_vals = calculate_net_values(tx[:values])
        values_str = net_vals.map { |v| "#{v[:amount].abs} #{v[:token]}" }.join(' | ')

        @transaction_counts[tx[:action]] ||= 0
        @transaction_counts[tx[:action]] += 1

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

  # --------------------------------------------------------------
  # Helper – collapse multiple entries of the same token into a net amount
  # --------------------------------------------------------------
  def calculate_net_values(values)
    net = Hash.new(0)
    token_names = {}
    values.each do |v|
      net[v[:token]] += v[:amount]
      token_names[v[:token]] = v[:token]
    end
    net.map { |tok, amt| { token: token_names[tok], amount: amt } }
  end

  # --------------------------------------------------------------
  # YEARLY & COMBINED TAX REPORTS (original logic – unchanged)
  # --------------------------------------------------------------
  def generate_summary_reports
    @years_processed.each { |year| generate_year_report(year) }
    generate_combined_report
    generate_address_reports   # <-- NEW: creates yaml/csv/summary for ≥5‑tx addresses
  end

  def generate_year_report(year)
    year_transactions = @all_transactions.select { |tx| tx[:date].year == year }
    return if year_transactions.empty?

    report_path = File.join(@output_reports_folder, "TON_Tax_Report_#{year}.txt")
    File.open(report_path, 'w') do |file|
      file.puts "TON Wallet Tax Report #{year}"
      file.puts "Generated on: #{Date.today}"
      file.puts '=' * 80
      file.puts

      # ---- Transaction statistics -------------------------------------------------
      file.puts '1. Transaction Statistics'
      file.puts '-' * 40
      file.puts "Total transactions: #{year_transactions.size}"

      # ---- Types -----------------------------------------------------------------
      type_counts = Hash.new(0)
      year_transactions.each { |tx| type_counts[tx[:action] || 'unknown'] += 1 }
      file.puts "\nTransaction types:"
      type_counts.each { |type, cnt| file.puts "#{type.capitalize}: #{cnt}" }

      # ---- TON movement -----------------------------------------------------------
      ton_mov = calculate_ton_movements(year_transactions)
      file.puts "\n2. TON Movements"
      file.puts '-' * 40
      file.puts "Sent: #{ton_mov[:sent].abs}"
      file.puts "Received: #{ton_mov[:received]}"
      file.puts "Net: #{ton_mov[:net]}"

      # ---- Jetton holdings --------------------------------------------------------
      file.puts "\n3. Jetton Holdings"
      file.puts '-' * 40
      @token_balances.each do |jetton, bal|
        next if jetton.downcase == 'ton'

        file.puts "#{jetton}: #{bal}"
      end
    end
  end

  def generate_combined_report
    report_path = File.join(@output_reports_folder, 'Combined_TON_Tax_Report.txt')
    File.open(report_path, 'w') do |file|
      file.puts 'Combined TON Wallet Tax Report'
      file.puts "Generated on: #{Date.today}"
      file.puts '=' * 80
      file.puts

      file.puts '1. Overall Statistics'
      file.puts '-' * 40
      file.puts "Total wallets processed: #{Dir.glob(File.join(@input_folder, '*.txt')).count}"
      file.puts "Total transactions processed: #{@all_transactions.size}"

      ton_mov = calculate_ton_movements(@all_transactions)
      file.puts "\n2. Combined TON Transactions"
      file.puts '-' * 40
      file.puts "Total TON sent: #{ton_mov[:sent].abs}"
      file.puts "Total TON received: #{ton_mov[:received]}"
      file.puts "Net TON movement: #{ton_mov[:net]}"

      file.puts "\n3. Combined Jetton Holdings"
      file.puts '-' * 40
      @token_balances.each do |jetton, bal|
        next if jetton.downcase == 'ton'

        file.puts "#{jetton}: #{bal}"
      end
    end
  end

  def calculate_ton_movements(transactions)
    sent = 0
    received = 0
    transactions.each do |tx|
      tx[:values].each do |val|
        next unless val[:token].downcase == 'ton'

        if val[:amount] < 0
          sent += val[:amount].abs
        else
          received += val[:amount]
        end
      end
    end
    { sent: sent, received: received, net: received - sent }
  end
  # --------------------------------------------------------------
  # NEW – generate the address‑>=5‑tx reports (yaml, csv, summary)
  # --------------------------------------------------------------
  def generate_address_reports
    # Keep only addresses with ≥5 occurrences (and not in the exception list)
    qualified = @address_stats.select { |_addr, data| data[:count] >= 5 }

    # ---------- Build rows (array of hashes) ----------
    rows = qualified.map do |addr, data|
      {
        address:    addr,
        tx_count:   data[:count],
        first_seen: data[:first_seen].iso8601,
        last_seen:  data[:last_seen].iso8601,
        category:   infer_category(addr).to_s
      }
    end

    # ---------- YAML output ----------
    yaml_path = File.join(@output_reports_folder, 'report.yaml')
    File.write(yaml_path, rows.to_yaml)

    # ---------- CSV output ----------
    csv_path = File.join(@output_reports_folder, 'report.csv')
    CSV.open(csv_path, 'w', write_headers: true,
                         headers: %w[address tx_count first_seen last_seen category]) do |csv|
      rows.each { |r| csv << r.values }
    end

    # ---------- Human‑readable summary ----------
    summary_path = File.join(@output_reports_folder, 'summary.txt')
    total_addresses = rows.size
    total_txs       = rows.sum { |r| r[:tx_count] }

    # Top 5 most active addresses
    top5 = rows.sort_by { |r| -r[:tx_count] }.first(5)

    # Distribution by category
    cat_dist = rows.each_with_object(Hash.new(0)) { |r, h| h[r[:category]] += 1 }

    summary = <<~TXT
      ── TON Address Activity Summary ────────────────────────────────────────
      Total distinct addresses (≥5 txs, exceptions excluded): #{total_addresses}
      Total transactions represented                           : #{total_txs}

      ── Top 5 active addresses ───────────────────────────────────────────────
      #{top5.map { |r| "  • #{r[:address]} – #{r[:tx_count]} txs (#{r[:category]})" }.join("\n")}

      ── Category distribution ────────────────────────────────────────────────
      #{cat_dist.map { |cat, cnt| "  • #{cat}: #{cnt}" }.join("\n")}

      ── Global date range ───────────────────────────────────────────────────
      Earliest transaction: #{rows.map { |r| r[:first_seen] }.min}
      Latest   transaction: #{rows.map { |r| r[:last_seen]  }.max}
    TXT

    File.write(summary_path, summary)
  end

  # --------------------------------------------------------------
  # Console‑side summary (unchanged from the original script)
  # --------------------------------------------------------------
  def display_summary
    puts "\nProcessing Summary:"
    puts '-' * 40
    puts "Total wallets processed: #{Dir.glob(File.join(@input_folder, '*.txt')).count}"
    puts "Total transactions processed: #{@all_transactions.size}"
    puts "Years processed: #{@years_processed.to_a.sort.join(', ')}"

    puts "\nTransaction Type Counts:"
    puts '-' * 40
    @transaction_counts.each do |type, count|
      puts "#{type.capitalize}: #{count}"
    end

    puts "\nReports generated in:"
    puts '-' * 40
    puts "Per‑wallet CSVs : #{@output_csv_folder}"
    puts "Tax & address reports : #{@output_reports_folder}"
  end
end

# ----------------------------------------------------------------------
# Run the processor
# ----------------------------------------------------------------------
processor = TonTransactionProcessor.new
processor.process_all_files
