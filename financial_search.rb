require 'csv'
require 'yaml'
require 'fileutils'

# Config
SEARCH_DIR = 'financial_institutions_csv'
OUTPUT_DIR = File.join('Processed', 'Financial_Search_Results')
YAML_OUTPUT_DIR = File.join(OUTPUT_DIR, 'yaml_files')
REPORT_OUTPUT_DIR = File.join(OUTPUT_DIR, 'reports')

def main
  keywords = if ARGV.any?
               ARGV.join(' ').split(/[,;]/).map(&:strip)
             else
               puts "Enter keywords to search for (comma or semicolon separated):"
               print "> "
               $stdin.gets.chomp.split(/[,;]/).map(&:strip)
             end

  if keywords.empty?
    puts "❌ Error: No keywords provided"
    exit(1)
  end

  keyword_data = {}
  keyword_regexes = keywords.map do |kw|
    regex = Regexp.new(kw.gsub(/\s+/, '.?'), Regexp::IGNORECASE)
    keyword_data[kw] = {
      regex: regex,
      matches: [],
      hit_counts: Hash.new(0),
      file_stats: Hash.new { |h, k| h[k] = { count: 0, amount: 0.0 } }
    }
    [kw, regex]
  end.to_h

  FileUtils.mkdir_p(YAML_OUTPUT_DIR)
  FileUtils.mkdir_p(REPORT_OUTPUT_DIR)

  csv_files = Dir.glob(File.join(SEARCH_DIR, '**', '*.csv'))
  if csv_files.empty?
    puts "⚠️ No CSV files found in #{SEARCH_DIR}"
    exit(1)
  end

  csv_files.each_with_index do |file, i|
    puts "\n📁 (#{i + 1}/#{csv_files.size}) Scanning: #{file}"
    scan_csv_file(file, keyword_data)
  end

  keyword_data.each do |kw, data|
    write_yaml_file(kw, data)
    write_report_file(kw, data)
  end

  puts "\n✅ Done. One YAML and report file per keyword saved in:"
  puts "   - YAML: #{YAML_OUTPUT_DIR}"
  puts "   - Reports: #{REPORT_OUTPUT_DIR}"
end

def scan_csv_file(file_path, keyword_data)
  headers = nil
  file_type = nil

  CSV.foreach(file_path, headers: true) do |row|
    headers ||= row.headers
    file_type ||= detect_file_type(headers)

    keyword_data.each do |kw, data|
      match_found = row.fields.any? { |f| f.to_s.match?(data[:regex]) }
      next unless match_found

      row_hash = row.to_h.merge({
        '_source_file' => file_path,
        '_file_type' => file_type
      })

      data[:matches] << row_hash

      row.fields.each do |f|
        if f.to_s.match?(data[:regex])
          data[:hit_counts][f.to_s] += 1
        end
      end

      amount = extract_amount(row, file_type)
      data[:file_stats][file_path][:count] += 1
      data[:file_stats][file_path][:amount] += amount
    end
  end
end

def write_yaml_file(keyword, data)
  yaml_path = File.join(YAML_OUTPUT_DIR, "#{keyword}.yaml")
  content = {
    keyword: keyword,
    total_matches: data[:matches].size,
    source_files: data[:file_stats].keys,
    file_stats: data[:file_stats],
    matches: data[:matches]
  }
  File.write(yaml_path, content.to_yaml)
end

def write_report_file(keyword, data)
  report_path = File.join(REPORT_OUTPUT_DIR, "#{keyword}_report.txt")

  total_amount = data[:file_stats].values.sum { |stat| stat[:amount] }

  File.open(report_path, 'w') do |f|
    f.puts "Report for keyword: #{keyword}"
    f.puts "=" * 80
    f.puts "Total matches: #{data[:matches].size}"
    f.puts "Total amount involved: $#{'%.2f' % total_amount}"
    f.puts "\nHits by Value:"
    data[:hit_counts].sort_by { |_, v| -v }.each do |val, count|
      f.puts "  #{val.ljust(40)} => #{count} matches"
    end
    f.puts "\nMatches by File:"
    data[:file_stats].each do |file, stats|
      f.puts "  #{File.basename(file)} => #{stats[:count]} matches, $#{'%.2f' % stats[:amount]}"
    end
    f.puts "\nSample Matches (first 5):"
    data[:matches].first(5).each_with_index do |match, i|
      f.puts "\n--- Match #{i + 1} ---"
      match.each { |k, v| f.puts "#{k}: #{v}" }
    end
  end
end

def detect_file_type(headers)
  if headers.include?('Received Currency') && headers.include?('Sent Currency')
    :crypto
  elsif headers.include?('Transaction Type') && headers.include?('Description')
    :bank_card
  elsif headers.include?('Withdrawal') && headers.include?('Balance')
    :bank_transaction
  else
    :unknown
  end
end

def extract_amount(row, type)
  case type
  when :bank_transaction
    row['Withdrawal'].to_f
  when :bank_card
    row['Transaction Amount'].to_f.abs
  when :crypto
    row['Sent Quantity'].to_f + row['Received Quantity'].to_f
  else
    0.0
  end
end

main
