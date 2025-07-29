require 'rtesseract'
require 'mini_magick'
require 'yaml'
require 'time'

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

  # Find subtotal: last $ amount before SUBTOTAL line
  subtotal_line_index = lines.index { |l| l =~ /subtotal/i }
  subtotal = nil
  if subtotal_line_index
    before_subtotal = lines[0...subtotal_line_index].reverse.find { |l| l =~ /\$\s*([\d,.]+)/ }
    subtotal = before_subtotal ? before_subtotal.match(/\$\s*([\d,.]+)/)[1].gsub(',', '').to_f : nil
  end
  # fallback subtotal sum of item amounts
  subtotal ||= data[:items].map { |it| it[:amount] }.sum.round(2)
  data[:subtotal] = subtotal

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

  # Calculate total_paid = subtotal + taxes
  total = subtotal
  total += subtotal * gst_percent / 100.0 if gst_percent
  total += subtotal * pst_percent / 100.0 if pst_percent
  data[:total_paid] = total.round(2)

  data
end

# Main processing loop for all images in folder
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

# Run and save YAML report
if __FILE__ == $0
  images_folder = './invoicesnreciepts'  # Change to your folder path
  report = process_images(images_folder)

  output_dir = 'Processed/OCR'
  output_file = File.join(output_dir, 'ocr_report.yaml')

  Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

  File.open(output_file, 'w') do |f|
    f.write(report.to_yaml)
  end
  puts "OCR processing complete. Report saved to Processed/OCR/ocr_report.yaml"

end
