require 'date'
require 'yaml'
require 'fileutils'

class NonTonJettonDetailExtractor
  def initialize
    @input_dir = 'CSV_Dumps/TON'
    @output_file = 'Processed/NonTON/non_ton_jetton_detailed.yaml'
    FileUtils.mkdir_p(File.dirname(@output_file))
  end

  def run
    result = []

    Dir.glob(File.join(@input_dir, 'TON_*.txt')).each do |file_path|
      wallet = File.basename(file_path, '.txt').sub('TON_', '')

      File.foreach(file_path) do |line|
        line.strip!
        line = line.gsub('−', '-').gsub("\u202F", ' ')  # Normalize symbols

        # Match: DATE [+/-] AMOUNT JETTON (optional tx)
        if line =~ /^(\d{4}-\d{2}-\d{2})\s+([+\-])\s*([\d,]+(?:\.\d+)?)\s*([A-Za-z0-9_]+)(?:.*tx[:\s]?([A-Za-z0-9]+))?/i
          date_str = $1
          sign = $2 == '+' ? 1 : -1
          amount = $3.gsub(',', '').to_f * sign
          jetton = $4.upcase
          tx = $5

          next if jetton == 'TON'
          next if amount.abs < 1e-9

          result << {
            wallet: wallet,
            date: date_str,
            jetton: jetton,
            amount: amount,
            tx: tx
          }
        end
      end
    end

    File.write(@output_file, result.to_yaml)
    puts "✅ Extracted #{result.size} non-TON jetton entries with dates to #{@output_file}"
  end
end

NonTonJettonDetailExtractor.new.run
