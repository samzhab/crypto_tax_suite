require 'fileutils'
require 'yaml'

# Define the folder paths
input_folder = 'CSV_Dumps/TON'
output_folder = 'Processed/TON/Logs'
output_file = 'txt_report.yaml'

# Ensure the output folder exists
FileUtils.mkdir_p(output_folder) unless File.directory?(output_folder)

# Initialize a hash to store the count of dates per file
report = {}

# Define a regular expression to match the date format "06 Jul 2024"
date_pattern = /\b\d{2} \w{3} \d{4}\b/

# Iterate over all txt files in the input folder
Dir.glob("#{input_folder}/*.txt") do |file|
  begin
    # Read the file content
    file_content = File.read(file)

    # Count the dates using the defined regex pattern
    date_count = file_content.scan(date_pattern).size

    # Add the count to the report with the file name
    report[File.basename(file)] = date_count
  rescue StandardError => e
    puts "Error processing file #{file}: #{e.message}"
  end
end

# Write the report to the output file in the Logs folder
output_path = File.join(output_folder, output_file)
File.open(output_path, 'w') do |file|
  file.write(YAML.dump(report))
end

puts "Report generated at #{output_path}"
