require 'yaml'
require 'fileutils'

# Define the folder paths
input_folder = 'Processed/TON/YAML'
output_folder = 'Processed/TON/Logs'
output_file = 'yaml_report.yaml'

# Ensure the output folder exists
FileUtils.mkdir_p(output_folder) unless File.directory?(output_folder)

# Initialize a hash to store the count of dates per file
report = {}

# Iterate over all YAML files in the input folder
Dir.glob("#{input_folder}/*.yaml") do |file|
  begin
    # Load the YAML file
    yaml_data = YAML.load_file(file)

    # Count the dates in the :transactions section
    if yaml_data && yaml_data[:transactions]
      date_count = yaml_data[:transactions].count { |transaction| transaction[:date] }

      # Add the count to the report with the file name
      report[File.basename(file)] = date_count
    end
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
