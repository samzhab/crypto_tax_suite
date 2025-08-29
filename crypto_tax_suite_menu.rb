require 'yaml'
require 'fileutils'
require 'date'
require 'byebug'
require_relative 'progress_tracker'

class CryptoTaxSuiteMenu
  def initialize
    @base_dir = File.dirname(__FILE__)
    @cache_dir = File.join(@base_dir, 'cache')
    @activity_cache_file = File.join(@cache_dir, 'activity_cache.yml')

    # Ensure cache directory exists
    FileUtils.mkdir_p(@cache_dir) unless Dir.exist?(@cache_dir)

    @first_run = !File.exist?(@activity_cache_file)
    setup_directories
    load_activity_cache

    # Initialize progress tracker
    @progress_tracker = ProgressTracker.new(@base_dir)

    show_welcome_message
    show_progress_summary
  end

  def load_activity_cache
    @activity_cache = if File.exist?(@activity_cache_file)
      YAML.load_file(@activity_cache_file) || {last_run: nil, changes: []}
    else
      {last_run: nil, changes: []}
    end
  rescue => e
    puts "⚠️ Warning: Could not load activity cache - #{e.message}"
    {last_run: nil, changes: []}
  end

  def show_progress_summary
    begin
      puts @progress_tracker.display_progress
      puts "\nPress enter to continue..."
      gets
    rescue => e
      puts "Error displaying progress: #{e.message}"
      puts "Press enter to continue..."
      gets
    end
  end
  
  def save_activity_cache
    File.write(@activity_cache_file, @activity_cache.to_yaml)
  rescue => e
    puts "⚠️ Warning: Could not save activity cache - #{e.message}"
  end

  def setup_directories
    %w[Processed Processed/OCR Processed/Financial_Search_Results Processed/FMV_values].each do |dir|
      FileUtils.mkdir_p(File.join(@base_dir, dir))
    end
  end

  def show_welcome_message
    system('clear') || system('cls')
    if @first_run
      puts "✨ First time running Crypto Tax Suite ✨"
    else
      last_run = @activity_cache[:last_run]
      puts "🕒 Last run: #{last_run ? Time.new(last_run) : 'Never'}"
      show_recent_changes
    end
    puts "\nPress enter to continue..."
    gets
  end

  def show_recent_changes
    return if @activity_cache[:changes].empty?

    puts "\n📋 Recent file changes:"
    @activity_cache[:changes].last(5).each do |change|
      emoji = case change[:action]
              when 'created' then '🆕'
              when 'modified' then '✏️'
              when 'deleted' then '🗑️'
              else '📄'
              end
      puts "#{emoji} #{change[:action].capitalize}: #{change[:file]}"
    end
  end

  def track_file_change(action, file_path)
    change = {
      timestamp: Time.now.utc.iso8601,
      action: action,
      file: File.basename(file_path),
      full_path: file_path
    }

    @activity_cache[:changes] << change
    @activity_cache[:last_run] = Time.now.utc.iso8601
    save_activity_cache

    emoji = case action
            when 'created' then '🆕'
            when 'modified' then '✏️'
            when 'deleted' then '🗑️'
            else '📄'
            end
    puts "\n#{emoji} File #{action}: #{File.basename(file_path)}"
  end

  def load_required_files
    # Load all your module files
    Dir[File.join(@base_dir, '*.rb')].each { |file| load file }
  end

  def display_main_menu
  loop do
    system('clear') || system('cls')
    puts "=== Crypto Tax Suite ==="
    puts "1. Process Invoices/Receipts (OCR)"
    puts "2. Process Transaction CSVs"
    puts "3. Process Transaction Dumps"
    puts "4. Explore Transaction Data"
    puts "5. Generate Tax Reports"
    puts "6. Financial Institution Search"
    puts "7. View Progress Report"
    puts "8. Exit"
    print "Select an option: "

    case gets.chomp.to_i
    when 1 then ocr_menu
    when 2 then csv_transaction_menu
    when 3 then dump_transaction_menu
    when 4 then explore_data_menu
    when 5 then tax_report_menu
    when 6 then financial_search_menu
    when 7 then
      if @progress_tracker
        begin
          current_status = @progress_tracker.scan_current_status
          @progress_tracker.save_progress(current_status)
          show_progress_summary
        rescue => e
          puts "Error generating progress report: #{e.message}"
          puts "Press enter to continue..."
          gets
        end
      else
        puts "Progress tracking not available"
        puts "Press enter to continue..."
        gets
      end
    when 8 then break
    else
      puts "Invalid option, please try again."
      puts "Press enter to continue..."
      gets
    end
  end
end

 def view_full_activity_log
   system('clear') || system('cls')
   puts "=== Full Activity Log ==="

   if @activity_cache[:changes].empty?
     puts "No activity recorded yet."
   else
     puts "🕒 Timestamp (UTC)\tAction\tFile"
     puts "-" * 50
     @activity_cache[:changes].each do |change|
       emoji = case change[:action]
               when 'created' then '🆕'
               when 'modified' then '✏️'
               when 'deleted' then '🗑️'
               else '📄'
               end
       puts "#{emoji} #{change[:timestamp]}\t#{change[:action].capitalize}\t#{change[:file]}"
     end
   end

   puts "\nTotal activities: #{@activity_cache[:changes].size}"
   gets
 end

  # Updated OCR menu with proper tracking
  def ocr_menu
    load 'ocr_analyzer.rb'
    analyzer = OcrAnalyzer.new

    loop do
      system('clear') || system('cls')
      puts "=== OCR Processing ==="
      puts "1. Process All Unprocessed Invoices"
      puts "2. Process Specific Invoice"
      puts "3. View OCR Report"
      puts "4. Back to Main Menu"
      print "Select an option: "

      case gets.chomp.to_i
      when 1
        puts "Processing all unprocessed invoices..."
        output_file = analyzer.process_all_invoices
        track_file_change('created', output_file)
        gets
      when 2
        files = Dir.glob("#{analyzer.images_folder}/*.{png,jpg,jpeg,pdf}")
        if files.empty?
          puts "No invoice files found!"
          gets
          next
        end
        puts "\nAvailable invoices:"
        files.each_with_index { |f, i| puts "#{i+1}. #{File.basename(f)}" }
        print "Enter file number or name: "
        input = gets.chomp

        if input.match?(/^\d+$/) && input.to_i.between?(1, files.size)
          file_path = files[input.to_i - 1]
          analyzer.process_single_invoice(File.basename(file_path))
          track_file_change('processed', file_path)
        else
          puts "Invalid selection"
        end
        gets
      when 3
          report = analyzer.view_report
          if report.is_a?(Array) && report.any?
            # Multiple reports/files were viewed
            report.each do |report_item|
              if report_item.respond_to?(:fetch) && report_item[:file_name]
                track_file_change('viewed', report_item[:file_name])
              end
            end
          elsif report.is_a?(String) || report.is_a?(Hash)
            # Single report was viewed
            track_file_change('viewed', analyzer.output_file)
          else
            puts "No report data found"
          end
          # Always track viewing the main output file
          track_file_change('viewed', analyzer.output_file)
        gets
      when 4 then break
      else puts "Invalid option, please try again."
      end
    end
  end

  def csv_transaction_menu
    loop do
      system('clear') || system('cls')
      puts "=== CSV Transaction Processing ==="
      puts "1. Process All CSV Files"
      puts "2. Process Specific Chain (ETH, SOLANA, etc.)"
      puts "3. Check Wallet Activity"
      puts "4. Back to Main Menu"
      print "Select an option: "

      case gets.chomp.to_i
      when 1
        puts "Processing all CSV files..."
        load 'chains_formatter.rb'
        puts "CSV processing completed."
        gets
      when 2
        print "Enter chain name (ETH, SOLANA, etc.): "
        chain = gets.chomp.upcase
        # Implement chain-specific processing
        puts "Processing #{chain} CSV files..."
        gets
      when 3
        puts "Generating wallet activity report..."
        load 'dump_scanner.rb'
        puts "Wallet report generated in wallet_analysis_report.txt"
        gets
      when 4 then break
      else puts "Invalid option, please try again."
      end
    end
  end

  def dump_transaction_menu
    loop do
      system('clear') || system('cls')
      puts "=== Transaction Dump Processing ==="
      puts "1. Process TON Dumps"
      puts "2. Process Non-TON Jettons"
      puts "3. Verify TON Formatting"
      puts "4. Back to Main Menu"
      print "Select an option: "

      case gets.chomp.to_i
      when 1
        puts "Processing TON dump files..."
        load 'ton_formatter.rb'
        puts "TON dump processing completed."
        gets
      when 2
        puts "Processing Non-TON jettons..."
        load 'non_ton_formatter.rb'
        puts "Non-TON jetton processing completed."
        gets
      when 3
        puts "Verifying TON formatting..."
        load 'check_ton_format.rb'
        puts "TON format verification completed."
        gets
      when 4 then break
      else puts "Invalid option, please try again."
      end
    end
  end

  def explore_data_menu
    loop do
      system('clear') || system('cls')
      puts "=== Explore Transaction Data ==="
      puts "1. Search by Chain"
      puts "2. Search by Year"
      puts "3. Search by Keyword"
      puts "4. Search by Wallet"
      puts "5. Back to Main Menu"
      print "Select an option: "

      case gets.chomp.to_i
      when 1
        print "Enter chain name (ETH, SOLANA, etc.): "
        chain = gets.chomp.upcase
        # Implement chain search
        puts "Searching #{chain} transactions..."
        gets
      when 2
        print "Enter year: "
        year = gets.chomp
        # Implement year search
        puts "Searching transactions from #{year}..."
        gets
      when 3
        print "Enter keyword: "
        keyword = gets.chomp
        # Implement keyword search
        puts "Searching for '#{keyword}'..."
        gets
      when 4
        print "Enter wallet address: "
        wallet = gets.chomp
        # Implement wallet search
        puts "Searching transactions for wallet #{wallet[0..10]}..."
        gets
      when 5 then break
      else puts "Invalid option, please try again."
      end
    end
  end

  def tax_report_menu
    progress = @progress_tracker.generate_progress_report
    overall = progress[:categories][:overall]
    unless overall[:ready_for_cra]
      puts "⚠️  System not ready for CRA reporting!"
      puts "Completion: #{overall[:overall_percentage]}%"
      puts "Please complete processing tasks first."
      gets
      return
    end
    require_relative 'crypto_tax_generator'
    puts "Defined classes: #{Object.constants.grep(/CryptoTax/)}" # Debug output
    generator = CryptoTaxGenerator.new
  loop do
    system('clear') || system('cls')
    puts "=== Tax Report Generation ==="
    puts "1. Generate Full Tax Report"
    puts "2. Generate Report by Chain"
    puts "3. Generate Report by Year"
    puts "4. Generate Report by Wallet"
    puts "5. View Generated Reports"
    puts "6. Back to Main Menu"
    print "Select an option: "

    case gets.chomp.to_i
    when 1
      result = generator.generate_full_report
      if result[:status] == :success
        track_file_change('created', result[:file])
        puts "✅ Full tax report generated: #{File.basename(result[:file])}"
      else
        puts "❌ Failed to generate full report"
      end
      gets

    when 2
      print "Enter chain name (ETH, SOLANA, etc.): "
      chain = gets.chomp.upcase
      result = generator.generate_chain_report(chain)
      if result[:status] == :success
        track_file_change('created', result[:file])
        puts "✅ #{chain} tax report generated: #{File.basename(result[:file])}"
      else
        puts "❌ Failed to generate #{chain} report"
      end
      gets

    when 3
      print "Enter year: "
      year = gets.chomp
      result = generator.generate_year_report(year)
      if result[:status] == :success
        track_file_change('created', result[:file])
        puts "✅ #{year} tax report generated: #{File.basename(result[:file])}"
      else
        puts "❌ Failed to generate #{year} report"
      end
      gets

    when 4
      print "Enter wallet address: "
      wallet = gets.chomp
      result = generator.generate_wallet_report(wallet)
      if result[:status] == :success
        track_file_change('created', result[:file])
        puts "✅ Wallet #{wallet[0..8]}... tax report generated: #{File.basename(result[:file])}"
      else
        puts "❌ Failed to generate wallet report"
      end
      gets

    when 5
      view_tax_reports(generator.output_dir)
      gets

    when 6
      break

    else
      puts "Invalid option, please try again."
    end
  end
end

def view_tax_reports(reports_dir)
  system('clear') || system('cls')
  puts "=== Generated Tax Reports ==="

  reports = Dir.glob(File.join(reports_dir, '*.yaml')).sort_by { |f| File.mtime(f) }.reverse

  if reports.empty?
    puts "No tax reports found"
    return
  end

  reports.each_with_index do |report, index|
    puts "#{index + 1}. #{File.basename(report)} (updated: #{File.mtime(report).strftime('%Y-%m-%d %H:%M')})"
  end

  print "\nEnter report number to view or 0 to go back: "
  choice = gets.chomp.to_i

  if choice.between?(1, reports.size)
    report_content = YAML.load_file(reports[choice - 1])
    puts "\nReport Content:"
    puts "-" * 40
    puts YAML.dump(report_content)
    track_file_change('viewed', reports[choice - 1])
  end
end

  def financial_search_menu
    loop do
      system('clear') || system('cls')
      puts "=== Financial Institution Search ==="
      puts "1. Search by Keyword"
      puts "2. Search by Date Range"
      puts "3. Search by Amount Range"
      puts "4. Back to Main Menu"
      print "Select an option: "

      case gets.chomp.to_i
      when 1
        print "Enter keywords (comma separated): "
        keywords = gets.chomp
        puts "Searching for #{keywords}..."
        load 'financial_search.rb'
        puts "Financial search completed."
        gets
      when 2
        print "Enter start date (YYYY-MM-DD): "
        start_date = gets.chomp
        print "Enter end date (YYYY-MM-DD): "
        end_date = gets.chomp
        puts "Searching between #{start_date} and #{end_date}..."
        gets
      when 3
        print "Enter minimum amount: "
        min = gets.chomp.to_f
        print "Enter maximum amount: "
        max = gets.chomp.to_f
        puts "Searching for amounts between #{min} and #{max}..."
        gets
      when 4 then break
      else puts "Invalid option, please try again."
      end
    end
  end

  def check_unprocessed_files(chain = nil, year = nil, wallet = nil)
    unprocessed = []

    # Check CSV_Dumps for unprocessed files
    Dir.glob(File.join(@base_dir, 'CSV_Dumps', '**', '*.{csv,txt}')).each do |file|
      # Skip if chain specified and doesn't match
      next if chain && !file.include?(chain)

      # Check if processed file exists
      processed_path = determine_processed_path(file)
      unless File.exist?(processed_path)
        unprocessed << file
      end
    end

    # Check for screenshots in invoices folder for the year
    if year
      Dir.glob(File.join(@base_dir, 'invoicesnreciepts', '**', '*.{png,jpg,jpeg}')).each do |img|
        if img.include?(year)
          # Check if this image has been OCR processed
          ocr_report = YAML.load_file('Processed/OCR/ocr_report.yaml') rescue {}
          unless ocr_report.values.any? { |entry| entry[:source_file] == img }
            unprocessed << img
          end
        end
      end
    end

    if unprocessed.any?
      puts "\nFound #{unprocessed.size} unprocessed files:"
      unprocessed.each { |f| puts " - #{File.basename(f)}" }

      print "\nDo you want to process these files now? (y/n): "
      if gets.chomp.downcase == 'y'
        # Process based on file type
        unprocessed.each do |file|
          if file.end_with?('.csv')
            load 'chains_formatter.rb'
          elsif file.end_with?('.txt')
            if file.include?('TON')
              load 'ton_formatter.rb'
            else
              load 'non_ton_formatter.rb'
            end
          elsif file.end_with?('.png', '.jpg', '.jpeg')
            load 'ocr_analyzer.rb'
          end
        end
      end
    else
      puts "No unprocessed files found matching your criteria."
    end
  end

  def determine_processed_path(csv_path)
    # Implement logic to determine where the processed file should be
    # This is a simplified version - adjust based on your actual file structure
    if csv_path.include?('CSV_Dumps/TON')
      filename = File.basename(csv_path, '.txt')
      File.join(@base_dir, 'Processed', 'TON', 'YAML', "#{filename}.yaml")
    else
      filename = File.basename(csv_path, '.csv')
      chain = csv_path.split('/').last.split('-').first.upcase
      File.join(@base_dir, 'Processed', chain, 'YAML', "#{filename}.yaml")
    end
  end
end

# Start the menu system
menu = CryptoTaxSuiteMenu.new
menu.display_main_menu
