require 'rtesseract'
require 'mini_magick'
require 'yaml'
require 'time'
require 'byebug'

class OcrAnalyzer
   attr_reader :images_folder, :output_file  # This creates a getter for @images_folder

  def initialize
    @images_folder = './invoicesnreciepts'
    @output_dir = 'Processed/OCR'
    @output_file = File.join(@output_dir, 'ocr_report.yaml')
    FileUtils.mkdir_p(@output_dir) unless Dir.exist?(@output_dir)
  end

  # Process all invoices in the folder
  def process_all_invoices
    report = process_images(@images_folder)
    save_report(report)
    puts "Processed #{report.size} invoices"
  end

  # Process a single invoice file
  def process_single_invoice(filename = nil)
    # Get list of available invoice files
    available_files = Dir.glob("#{@images_folder}/*.{png,jpg,jpeg,tiff,pdf}").map { |f| File.basename(f) }
    if available_files.empty?
      puts "No invoice files found in #{@images_folder}"
      return
    end
    # If no filename provided, show interactive selection
    puts "\nAvailable invoices:"
    available_files.each_with_index { |f, i| puts "#{i+1}. #{f}" }
    puts "\n0. Cancel"
    print "Enter file number or partial name: "
    input = gets.chomp.strip

    return if input == '0'

    # Handle numeric selection
    if input.match(/^\d+$/) && input.to_i.between?(1, available_files.size)
      filename = available_files[input.to_i - 1]
    else
      # Try to find matching filename
      matches = available_files.select { |f| f.downcase.include?(input.downcase) }
      case matches.size
      when 0
        puts "No files match '#{input}'"
        return
      when 1
        filename = matches.first
      else
        puts "Multiple matches found:"
        matches.each_with_index { |f, i| puts "#{i+1}. #{f}" }
        print "Select which file to process: "
        selection = gets.chomp.to_i
        return unless selection.between?(1, matches.size)
        filename = matches[selection - 1]
      end
    end

    full_path = File.join(@images_folder, filename)
    unless File.exist?(full_path)
      puts "File not found: #{filename}"
      return
    end

    begin
      puts "Processing #{filename}..."
      preprocessed_path = preprocess_image(full_path)
      ocr_text = RTesseract.new(preprocessed_path, lang: 'eng').to_s
      data = extract_invoice_data(ocr_text)

      report = [{
        file_name: filename,
        processed_at: Time.now.iso8601,
        extracted_data: data
      }]

      save_report(report)
      puts "Successfully processed: #{filename}"
      puts "Merchant: #{data[:merchant]}" if data[:merchant]
      puts "Date: #{data[:date]}" if data[:date]
      puts "Total Paid: $#{data[:total_paid]}"
    rescue => e
      puts "Error processing #{filename}: #{e.message}"
    ensure
      # Cleanup temp file
      File.delete(preprocessed_path) if preprocessed_path && File.exist?(preprocessed_path)
    end
  end

  # View the OCR report
  def view_report
    if File.exist?(@output_file)
      report = YAML.load_file(@output_file)
      puts YAML.dump(report)
      report
    else
      puts "No OCR report found. Process some invoices first."
    end
  end

  private

  # Preprocess image: grayscale + resize for better OCR
  def preprocess_image(image_path)
    img = MiniMagick::Image.open(image_path)
    img.colorspace 'Gray'
    img.resize '2000x2000>' # Resize if larger than 2000px
    tmp_path = "/tmp/preprocessed_#{File.basename(image_path)}"
    img.write(tmp_path)
    tmp_path
  end

  # Extract invoice data from OCR text
  def extract_invoice_data(text)
    lines = text.split(/\r?\n/).map(&:strip).reject(&:empty?)
    data = {}
    data[:items] = []

    # Merchant: try first line with 'mobile' or custom heuristics
    if m = text.match(/(public mobile|mobile)/i)
      data[:merchant] = m[1].strip.split.map(&:capitalize).join(' ')
    end

    # Date (e.g. Aug 14, 2024)
    if m = text.match(/(\b\w{3,9}\s+\d{1,2},\s+\d{4}\b)/)
      data[:date] = m[1]
    end

    # Extract items with $amount & descriptions
    lines.each_with_index do |line, i|
      if line =~ /\$\s*([\d,.]+)/  # capture $ amount
        amount = $1.gsub(',', '').to_f
        # Try to find item description: same line minus amount or previous line
        desc = line.sub(/\$\s*[\d,.]+/, '').strip
        desc = lines[i - 1].strip if desc.empty? && i > 0
        data[:items] << { description: desc, amount: amount }
      end
    end

    # Find total and subtotal by first finding dollar amounts and then looking for "total" or "subtotal" nearby
    total = nil
    subtotal = nil

    lines.each_with_index do |line, i|
      if line =~ /\$\s*([\d,.]+)/
        amount = $1.gsub(',', '').to_f

        # Check current line for total/subtotal keywords
        if line.downcase.include?('total') && !line.downcase.include?('subtotal')
          total = amount
        elsif line.downcase.include?('subtotal')
          subtotal = amount
        else
          # Check surrounding lines (previous and next) for total/subtotal keywords
          window = lines[[0, i-2].max..[lines.size-1, i+2].min].join(' ').downcase

          if window.include?('total') && !window.include?('subtotal')
            total = amount
          elsif window.include?('subtotal')
            subtotal = amount
          end
        end
      end
    end

    # If we found a total but no subtotal, use total as subtotal
    subtotal ||= total
    data[:subtotal] = subtotal if subtotal

    # Extract GST and PST percentages
    gst_percent = nil
    pst_percent = nil
    lines.each do |line|
      if line =~ /gst.*?(\d{1,2}\.?\d*)%/i
        gst_percent = $1.to_f
      elsif line =~ /pst.*?(\d{1,2}\.?\d*)%/i
        pst_percent = $1.to_f
      end
    end

    data[:taxes] = {}
    data[:taxes][:gst_percent] = gst_percent if gst_percent
    data[:taxes][:pst_percent] = pst_percent if pst_percent

    # Calculate total_paid if not found directly
    if total
      data[:total_paid] = total.round(2)
    else
      # Fallback calculation if we couldn't find total directly
      calculated_total = subtotal || 0
      calculated_total += subtotal * gst_percent / 100.0 if gst_percent
      calculated_total += subtotal * pst_percent / 100.0 if pst_percent
      data[:total_paid] = calculated_total.round(2)
    end

    data
  end

  # Process all images in folder
  def process_images(folder)
    report = []

    Dir.glob("#{folder}/*.{png,jpg,jpeg,tiff}") do |image_path|
      puts "Processing: #{image_path}"

      preprocessed_path = preprocess_image(image_path)
      ocr_text = RTesseract.new(preprocessed_path, lang: 'eng').to_s

      data = extract_invoice_data(ocr_text)
      report << {
        file_name: File.basename(image_path),
        processed_at: Time.now.iso8601,
        extracted_data: data
      }

      # Cleanup temp preprocessed file
      File.delete(preprocessed_path) if File.exist?(preprocessed_path)
    end

    report
  end

  def save_report(report)
    # Load existing report if it exists
    existing_report = []
    if File.exist?(@output_file)
      existing_report = YAML.load_file(@output_file) || []
    end

    # Merge new entries with existing ones, updating duplicates
    report.each do |new_entry|
      if existing_index = existing_report.find_index { |e| e[:file_name] == new_entry[:file_name] }
        existing_report[existing_index] = new_entry # update existing entry
      else
        existing_report << new_entry # add new entry
      end
    end

    File.open(@output_file, 'w') do |f|
      f.write(existing_report.to_yaml)
    end
  end
end

# Allow direct script execution while still working with menu system
if __FILE__ == $0
  analyzer = OcrAnalyzer.new
  analyzer.process_all_invoices
  puts "OCR processing complete. Report saved to #{analyzer.instance_variable_get(:@output_file)}"
end
