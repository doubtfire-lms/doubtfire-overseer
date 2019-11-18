# frozen_string_literal: true

require 'zip'

def ack_result(results_publisher, value, task_id)
  msg = { message: value, task_id: task_id }
  return if results_publisher.nil?

  results_publisher.connect_publisher
  results_publisher.publish_message msg
  results_publisher.disconnect_publisher
end

def valid_zip?(file)
  begin
    zip = Zip::File.open(file)
    return true
  rescue StandardError => e
    raise e
  ensure
    zip&.close
  end
  false
end

# Flat extract a zip file, no sub-directories.
def extract_zip(input_zip_file_path, output_loc)
  Zip::File.open(input_zip_file_path) do |zip_file|
    # Handle entries one by one
    zip_file.each do |entry|
      # Extract to file/directory/symlink
      puts "Extracting #{entry.name} #{entry.ftype}"
      pn = Pathname.new entry.name
      unless entry.ftype.to_s == 'directory'
        entry.extract "#{output_loc}/#{pn.basename}"
      end
    end
    # # Find specific entry
    # entry = zip_file.glob('*.csv').first
    # puts entry.get_input_stream.read
  end
end

def get_task_path(task_id)
  "student_projects/task_#{task_id}"
end

##################################################################
##################################################################

# Step 1 -- done
def extract_submission(zip_file, path)
  extract_zip zip_file, path
end

# Step 2 -- done
def extract_assessment(zip_file, path)
  extract_zip zip_file, path
end

# Step 3
def run_assessment_script(path)
  # TODO: Change this bad boy to docker stuff.
  rpath = "#{path}/run.sh"
  unless File.exist? rpath
    client_error!({ error: "File #{rpath} doesn't exist" }, 500)
  end
  result = {}

  `chmod +x #{rpath}`

  Dir.chdir path do
    result = { run_result: `./run.sh` }
  end
  result
end

# Step 4
def cleanup_after_your_own_mess(path)
  return if path.nil?
  return unless File.exist? path

  puts 'Recursively force removing: ' + path
  FileUtils.rm_rf path
end

def receive(channel, results_publisher, delivery_info, _properties, params)
  params = JSON.parse(params)
  puts params

  if params['task_id'].nil? || !params['task_id'].is_a?(Integer)
    client_error!({ error: "Invalid task_id: #{params['task_id']}" }, 400)
  end
  unless File.exist? params['submission']
    client_error!({ error: "Zip file not found: #{params['submission']}" }, 400)
  end
  unless File.exist? params['assessment']
    client_error!({ error: "Zip file not found: #{params['assessment']}" }, 400)
  end
  unless valid_zip? params['submission']
    client_error!({ error: "Invalid zip file: #{params['submission']}" }, 400)
  end
  unless valid_zip? params['assessment']
    client_error!({ error: "Invalid zip file: #{params['assessment']}" }, 400)
  end

  output_loc = get_task_path params['task_id']
  puts "Output loc: #{output_loc}"
  FileUtils.mkdir_p output_loc

  skip_rm = params[:skip_rm] || 0

  extract_submission params['submission'], output_loc
  extract_assessment params['assessment'], output_loc

  result = run_assessment_script output_loc
  puts result

  # channel.ack(delivery_info.delivery_tag)
rescue ClientException => _e
  cleanup_after_your_own_mess output_loc if skip_rm != 1
  channel.ack(delivery_info.delivery_tag)
  client_error!({ error: e.message }, e.status)
rescue ServerException
  cleanup_after_your_own_mess output_loc if skip_rm != 1
  channel.ack(delivery_info.delivery_tag)
  server_error!({ error: 'Internal server error', task_id: params['task_id'] }, 500)
rescue StandardError => _e
  cleanup_after_your_own_mess output_loc if skip_rm != 1
  channel.ack(delivery_info.delivery_tag)
  server_error!({ error: 'Internal server error', task_id: params['task_id'] }, 500)
else
  cleanup_after_your_own_mess output_loc if skip_rm != 1
  channel.ack(delivery_info.delivery_tag)
  ack_result results_publisher, result, params['task_id'] # unless results_publisher.nil?
end

# TODO: Change client_error!, server_error! and default_error! to publishers,
# instead of just logging the results! Oh and, make a logs queue!
# We also probably shouldn't be using HTTP status codes..
# All of these 3 methods should convey information about the task_id and it's
# submission count/attempt/number that ran into trouble.
