require 'yaml'
require 'fileutils'
require 'date'
require 'time'

class ProgressTracker
  def initialize(base_dir = nil)
    @base_dir = base_dir || File.dirname(__FILE__)
    @cache_dir = File.join(@base_dir, 'cache')
    @progress_file = File.join(@cache_dir, 'progress_report.yml')
    FileUtils.mkdir_p(@cache_dir) unless Dir.exist?(@cache_dir)
  end

  def scan_current_status
    {
      scanned_at: Time.now.utc.iso8601,
      csv_processing: scan_csv_status,
      fmv_data: scan_fmv_status,
      ocr_processing: scan_ocr_status,
      financial_search: scan_financial_search_status,
      ton_processing: scan_ton_status,
      overall: calculate_overall_status
    }
  end

  def scan_csv_status
    csv_dumps = Dir.glob(File.join(@base_dir, 'CSV_Dumps', '**', '*.csv'))
    processed_yamls = Dir.glob(File.join(@base_dir, 'Processed', '**', '*.yaml'))

    # Only count YAML files in chain-specific directories, not all YAML files
    chain_yamls = Dir.glob(File.join(@base_dir, 'Processed', '*', 'YAML', '*.yaml'))

    chains_in_dumps = Dir.glob(File.join(@base_dir, 'CSV_Dumps', '*'))
      .select { |f| File.directory?(f) }
      .map { |f| File.basename(f) }

    chains_processed = Dir.glob(File.join(@base_dir, 'Processed', '*'))
      .select { |f| File.directory?(f) }
      .map { |f| File.basename(f) }
      .reject { |name| ['Financial_Search_Results', 'FMV_values', 'OCR', 'NonTON'].include?(name) }

    {
      total_csv_files: csv_dumps.size,
      processed_yaml_files: chain_yamls.size,  # Use chain-specific YAMLs only
      chains_found: chains_in_dumps,
      chains_processed: chains_processed,
      completion_percentage: calculate_percentage(chain_yamls.size, csv_dumps.size),
      ready: chain_yamls.size >= csv_dumps.size * 0.8
    }
  end

  def scan_fmv_status
    fmv_dir = File.join(@base_dir, 'Processed', 'FMV_values')
    return { available: false, ready: false } unless Dir.exist?(fmv_dir)

    fmv_files = Dir.glob(File.join(fmv_dir, '*.yaml'))
    multi_chain_file = File.join(fmv_dir, 'multi_chain_fmv_cad.yaml')

    has_data = File.exist?(multi_chain_file) && File.size(multi_chain_file) > 100
    {
      available: true,
      ready: has_data,
      total_files: fmv_files.size,
      has_multi_chain: has_data
    }
  end

  def scan_ocr_status
  ocr_dir = File.join(@base_dir, 'Processed', 'OCR')
  return { available: false, ready: false } unless Dir.exist?(ocr_dir)

  ocr_files = Dir.glob(File.join(ocr_dir, '*.yaml'))
  ocr_report = File.join(ocr_dir, 'ocr_report.yaml')
  invoice_files = Dir.glob(File.join(@base_dir, 'invoicesnreciepts', '*.{png,jpg,jpeg,pdf}'))

  # Check if report file exists and has content
  has_report = File.exist?(ocr_report) && File.size(ocr_report) > 50

  processed_count = 0
  if has_report
    begin
      report_data = YAML.load_file(ocr_report)
      # Handle various possible return values from YAML.load_file
      if report_data.is_a?(Array)
        processed_count = report_data.size
      elsif report_data.is_a?(Hash)
        processed_count = report_data.keys.size
      else
        processed_count = 0
      end
    rescue => e
      puts "Warning: Could not read OCR report: #{e.message}"
      processed_count = 0
    end
  end

  {
    available: true,
    ready: has_report && processed_count > 0,
    total_invoices: invoice_files.size,
    processed_invoices: processed_count,
    completion_percentage: calculate_percentage(processed_count, invoice_files.size)
  }
end

  def scan_financial_search_status
    fs_dir = File.join(@base_dir, 'Processed', 'Financial_Search_Results')
    return { available: false, ready: false } unless Dir.exist?(fs_dir)

    yaml_files = Dir.glob(File.join(fs_dir, 'yaml_files', '*.yaml'))
    report_files = Dir.glob(File.join(fs_dir, 'reports', '*.yaml'))
    source_files = Dir.glob(File.join(@base_dir, 'financial_institutions_csv', '**', '*.csv'))

    # Financial search is ready if we have at least some reports
    has_reports = report_files.size > 0
    has_yaml_data = yaml_files.size > 0

    {
      available: true,
      ready: has_reports || has_yaml_data,  # Ready if we have either reports or YAML data
      yaml_files: yaml_files.size,
      report_files: report_files.size,
      source_files: source_files.size,
      completion_percentage: calculate_percentage((report_files.size + yaml_files.size), source_files.size * 2)
    }
  end

  def scan_ton_status
    ton_yamls = Dir.glob(File.join(@base_dir, 'Processed', 'TON', 'YAML', '*.yaml'))
    non_ton_yamls = Dir.glob(File.join(@base_dir, 'Processed', 'NonTON', '*.yaml'))
    ton_dumps = Dir.glob(File.join(@base_dir, 'CSV_Dumps', 'TON', '*.txt'))

    ton_ready = ton_yamls.size >= ton_dumps.size * 0.9
    {
      ton_processed: ton_yamls.size,
      non_ton_processed: non_ton_yamls.size,
      total_dumps: ton_dumps.size,
      ton_ready: ton_ready,
      completion_percentage: calculate_percentage(ton_yamls.size, ton_dumps.size)
    }
  end

  def calculate_overall_status
    csv_status = scan_csv_status
    fmv_status = scan_fmv_status
    ocr_status = scan_ocr_status
    fs_status = scan_financial_search_status
    ton_status = scan_ton_status

    tasks = [csv_status, fmv_status, ocr_status, fs_status, ton_status]

    completion_percentages = tasks.map do |cat|
      # Use the category's completion percentage if available, otherwise base on readiness
      cat[:completion_percentage] || (cat[:ready] ? 100 : 0)
    end

    # Cap percentages at 100% to avoid unrealistic numbers
    completion_percentages.map! { |p| [p, 100].min }

    all_ready = tasks.all? { |cat| cat[:ready] }

    {
      completion_percentage: (completion_percentages.sum / completion_percentages.size).round(2),
      ready_for_cra: all_ready,
      total_tasks: tasks.size,
      ready_tasks: tasks.count { |cat| cat[:ready] }
    }
  end

  def calculate_percentage(completed, total)
    return 100 if total.zero? && completed.zero?
    return 0 if total.zero?
    ((completed.to_f / total) * 100).round(2)
  end

  def get_cached_progress
    return {} unless File.exist?(@progress_file)

    cached = YAML.load_file(@progress_file) rescue {}
    # If cache is more than 1 hour old, consider refreshing
    if cached[:scanned_at] && (Time.now - Time.parse(cached[:scanned_at])) > 3600
      return scan_current_status
    end
    cached
  rescue
    scan_current_status
  end

  def save_progress(status)
    File.write(@progress_file, status.to_yaml)
  end

  def display_progress
    status = get_cached_progress
    return "No progress data available" if status.empty?

    summary = []
    summary << "📊 CRYPTO TAX SUITE - CURRENT STATUS"
    scanned_at = Time.parse(status[:scanned_at].to_s).utc
    summary << "Last scanned: #{scanned_at.strftime("%B %-d, %Y at %-l:%M %p UTC")}"
    summary << ""

    # CSV Processing
    csv = status[:csv_processing] || {}
    summary << "📁 CSV Processing: #{csv[:completion_percentage]}%"
    summary << "   #{csv[:processed_yaml_files]}/#{csv[:total_csv_files]} files"
    summary << "   #{csv[:chains_processed].size}/#{csv[:chains_found].size} chains"
    summary << "   Ready: #{csv[:ready] ? '✅' : '❌'}"

    # FMV Data
    fmv = status[:fmv_data] || {}
    summary << "💰 FMV Data: #{fmv[:available] ? '✅' : '❌'}"
    summary << "   Ready: #{fmv[:ready] ? '✅' : '❌'}" if fmv[:available]

    # OCR Processing
    ocr = status[:ocr_processing] || {}
    summary << "🧾 OCR Processing: #{ocr[:available] ? '✅' : '❌'}"
    if ocr[:available]
      summary << "   #{ocr[:processed_invoices]}/#{ocr[:total_invoices]} invoices"
      summary << "   Ready: #{ocr[:ready] ? '✅' : '❌'}"
    end

    # Financial Search
    fs = status[:financial_search] || {}
    summary << "💳 Financial Search: #{fs[:available] ? '✅' : '❌'}"
    summary << "   Ready: #{fs[:ready] ? '✅' : '❌'}" if fs[:available]

    # TON Processing
    ton = status[:ton_processing] || {}
    summary << "⚡ TON Processing: #{ton[:completion_percentage]}%"
    summary << "   #{ton[:ton_processed]}/#{ton[:total_dumps]} files"
    summary << "   Ready: #{ton[:ton_ready] ? '✅' : '❌'}"

    # Overall
    overall = status[:overall] || {}
    summary << ""
    summary << "🎯 OVERALL PROGRESS: #{overall[:completion_percentage]}%"
    summary << "📋 CRA Ready: #{overall[:ready_for_cra] ? '✅ YES' : '❌ NO'}"
    summary << "   #{overall[:ready_tasks]}/#{overall[:total_tasks]} tasks ready"

    summary.join("\n")
  end
end

# Standalone execution
if __FILE__ == $0
  tracker = ProgressTracker.new
  tracker.generate_progress_report
  puts tracker.display_progress_summary
end
