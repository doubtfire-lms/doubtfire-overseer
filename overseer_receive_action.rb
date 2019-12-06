# frozen_string_literal: true

require 'zip'
require 'securerandom'
require 'yaml'

module Execution
  RUN = 'run'
  BUILD = 'build'
  HOST_DIR = 'app'
  DOCKER_WORKDIR = 'home/hermit/app'
  DOCKER_OUTDIR = 'var/lib/overseer'
  CONTAINER_NAME = 'container1'
end

def ack_result(results_publisher, task_id, timestamp, output_path)
  return if results_publisher.nil?

  msg = { task_id: task_id, timestamp: timestamp }

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

def host_parent_path
  # Docker volumes needs absolute source and destination paths
  "#{Dir.pwd}/#{Execution::HOST_DIR}"
end

def host_exec_path
  # Docker volumes needs absolute source and destination paths
  "#{Dir.pwd}/#{Execution::HOST_DIR}/sandbox"
end

def host_output_path
  # Docker volumes needs absolute source and destination paths
  "#{Dir.pwd}/#{Execution::HOST_DIR}/output"
end

def force_remove_container
  puts "Force removing container: #{Execution::CONTAINER_NAME}"
  `docker container rm -vf #{Execution::CONTAINER_NAME}`
end

##################################################################
##################################################################

# Step 1
def copy_student_files(s_path)
  puts 'Copying submission files'
  `cp -R #{s_path}/. #{host_exec_path}`
end

def extract_submission(zip_file)
  puts 'Extracting submission from zip file'
  extract_zip zip_file, host_exec_path
end

# Step 2
def extract_assessment(zip_file)
  extract_zip zip_file, host_exec_path
end

# Step 3
def run_assessment_script_via_docker(output_path, random_string, exec_mode, command, tag)
  client_error!({ error: "A valid Docker image name:tag is needed" }, 400) if tag.nil? || tag.to_s.strip.empty?
  force_remove_container

  puts 'Running docker executable..'

  # TODO: Security:
  # Pass random filename... both `blah.txt` and `blah.yaml`
  # Permit write access ONLY to these files
  # Other security like no network access, capped execution time + resources, etc

  # test:
  # -m 100MB done
  # --stop-timeout 10 (seconds) (isn't for what I thought it was :))
  # --network none (fails reading from https://api.nuget.org/v3/index.json)
  # --read-only (FAILURE without correct exit code)
  # https://docs.docker.com/engine/reference/run/#security-configuration
  # https://docs.docker.com/engine/reference/run/#runtime-constraints-on-resources
  # -u="overseer" (specify default non-root user)

  result = {
    run_result_message:
    `timeout 20 docker run \
    -m 100MB \
    --restart no \
    --cpus 1 \
    --volume #{host_exec_path}:/#{Execution::DOCKER_WORKDIR} \
    --volume #{host_output_path}:/#{Execution::DOCKER_OUTDIR} \
    --name #{Execution::CONTAINER_NAME} \
    #{tag} \
    /bin/bash -c "#{command}"`
  }

  exitstatus = $?.exitstatus
  extract_result_files host_output_path, output_path, random_string, $?.exitstatus

  diff_result = `docker diff #{Execution::CONTAINER_NAME}`
  extract_docker_diff_file output_path, diff_result, exec_mode

  puts "Docker run command execution status code: #{exitstatus}"

  if exitstatus != 0
    raise Subscriber::ServerException.new result, 500
  end
end

# Step 4
def extract_result_files(s_path, output_path, random_string, exitstatus)
  client_error!({ error: "A valid output_path is needed" }, 400) if output_path.nil? || output_path.to_s.strip.empty?

  puts 'Extracting result file from the pit..'
  FileUtils.mkdir_p output_path

  input_txt_file_name = "#{s_path}/#{random_string}.txt"
  output_txt_file_name = "#{output_path}/output.txt"
  input_yaml_file_name = "#{s_path}/#{random_string}.yaml"
  output_yaml_file_name = "#{output_path}/output.yaml"

  # Process .txt file.
  if File.exist? input_txt_file_name
    File.open(input_txt_file_name, 'a') { |f|
      f.puts "exit code: #{exitstatus}"
    }

    if File.exist? output_txt_file_name
      to_append = File.read input_txt_file_name
      File.open(output_txt_file_name, 'a') { |f|
        f.puts ''
        f.puts to_append
      }
    else
      FileUtils.copy(input_txt_file_name, output_txt_file_name)
    end

    FileUtils.rm input_txt_file_name
  else
    puts "Results file: #{s_path}/#{random_string}.txt does not exist"
  end

  # Process .yaml file.
  if File.exist? input_yaml_file_name
    File.open(input_yaml_file_name, 'a') { |f|
      f.puts "exit_code: #{exitstatus}"
    }

    if File.exist? output_yaml_file_name
      output_yaml = YAML.load_file(output_yaml_file_name)
      input_yaml = YAML.load_file(input_yaml_file_name)

      # Merge yaml files.
      output_yaml.merge! input_yaml
      File.open(output_yaml_file_name, 'w') { |f|
        f.puts output_yaml.to_yaml
      }
    else
      FileUtils.copy(input_yaml_file_name, output_yaml_file_name)
    end

    FileUtils.rm input_yaml_file_name
  else
    puts "Results file: #{s_path}/#{random_string}.yaml does not exist"
  end

end

# Step 5
def extract_docker_diff_file(output_path, diff_result, exec_mode)
  File.write("#{output_path}/#{exec_mode}-diff.txt", "docker diff: \n#{!diff_result&.strip&.empty? ? diff_result : 'nothing changed' }")
end

# Step 6
def cleanup_host_parent_path
  path = host_parent_path
  return if path.nil?
  return unless File.exist? path

  puts "Recursively force removing: #{path}/*"
  FileUtils.rm_rf(Dir.glob("#{path}/*"))
end

def valid_zip_file_param?(params)
  !params['zip_file'].nil? && params['zip_file'].is_a?(Integer) && params['zip_file'] == 1
end

def receive(subscriber_instance, channel, results_publisher, delivery_info, _properties, params)
  params = JSON.parse(params)
  return subscriber_instance.client_error!({error: 'PARAM `docker_image_name_tag` is required'}, 400) if params['docker_image_name_tag'].nil?
  return subscriber_instance.client_error!({error: 'PARAM `output_path` is required'}, 400) if params['output_path'].nil?
  return subscriber_instance.client_error!({error: 'PARAM `submission` is required'}, 400) if params['submission'].nil?
  return subscriber_instance.client_error!({error: 'PARAM `assessment` is required'}, 400) if params['assessment'].nil?
  return subscriber_instance.client_error!({error: 'PARAM `timestamp` is required'}, 400) if params['timestamp'].nil?
  return subscriber_instance.client_error!({error: 'PARAM `task_id` is required'}, 400) if params['task_id'].nil?

  if !ENV['RUBY_ENV'].nil? && ENV['RUBY_ENV'] == 'development'
    puts 'Running in development mode.'\
    ' Prepending ROOT_PATH to submission, assessment and output_path params.'
    root_path = ENV['ROOT_PATH']
    params['output_path'] = "#{root_path}#{params['output_path']}"
    params['submission'] = "#{root_path}#{params['submission']}"
    params['assessment'] = "#{root_path}#{params['assessment']}"
  end

  puts params

  docker_image_name_tag = params['docker_image_name_tag']
  output_path = params['output_path']
  submission = params['submission']
  assessment = params['assessment']
  timestamp = params['timestamp']
  task_id = params['task_id']

  unless task_id.is_a?(Integer)
    subscriber_instance.client_error!({ error: "Invalid task_id: #{task_id}" }, 400)
  end

  unless File.exist? submission
    if valid_zip_file_param? params
      subscriber_instance.client_error!({ error: "Zip file not found: #{submission}" }, 400)
    else
      # By default, Overseer will expect a folder path
      subscriber_instance.client_error!({ error: "Folder not found: #{submission}" }, 400)
    end
  end

  unless File.exist? assessment
    subscriber_instance.client_error!({ error: "Zip file not found: #{assessment}" }, 400)
  end

  unless valid_zip? submission
    subscriber_instance.client_error!({ error: "Invalid zip file: #{submission}" }, 400)
  end

  unless valid_zip? assessment
    subscriber_instance.client_error!({ error: "Invalid zip file: #{assessment}" }, 400)
  end

  puts "Docker execution path: #{host_parent_path}"
  if File.exist? host_parent_path
    cleanup_host_parent_path
  end
  # TODO: Add correct permissions here
  FileUtils.mkdir_p host_exec_path
  FileUtils.mkdir_p host_output_path

  skip_rm = params['skip_rm'] || 0

  if valid_zip_file_param? params
    extract_submission submission
  else
    copy_student_files submission
  end

  extract_assessment assessment

  random_string = "#{Execution::BUILD}-#{SecureRandom.hex}"
  run_assessment_script_via_docker(
    output_path,
    random_string,
    Execution::BUILD,
    "chmod u+x /#{Execution::DOCKER_WORKDIR}/#{Execution::BUILD}.sh && /#{Execution::DOCKER_WORKDIR}/#{Execution::BUILD}.sh /#{Execution::DOCKER_OUTDIR}/#{random_string}.yaml >> /#{Execution::DOCKER_OUTDIR}/#{random_string}.txt",
    docker_image_name_tag
  )
  random_string = "#{Execution::RUN}-#{SecureRandom.hex}"
  run_assessment_script_via_docker(
    output_path,
    random_string,
    Execution::RUN,
    "chmod u+x /#{Execution::DOCKER_WORKDIR}/#{Execution::RUN}.sh && /#{Execution::DOCKER_WORKDIR}/#{Execution::RUN}.sh /#{Execution::DOCKER_OUTDIR}/#{random_string}.yaml >> /#{Execution::DOCKER_OUTDIR}/#{random_string}.txt",
    docker_image_name_tag
  )

rescue Subscriber::ClientException => e
  channel.ack(delivery_info.delivery_tag)
  puts e.message
  subscriber_instance.client_error!({ error: e.message, task_id: task_id, timestamp: timestamp }, e.status)
rescue Subscriber::ServerException => e
  channel.ack(delivery_info.delivery_tag)
  puts e.message
  subscriber_instance.server_error!({ error: 'Internal server error', task_id: task_id, timestamp: timestamp }, 500)
rescue StandardError => e
  channel.ack(delivery_info.delivery_tag)
  puts e.message
  subscriber_instance.server_error!({ error: 'Internal server error', task_id: task_id, timestamp: timestamp }, 500)
else
  channel.ack(delivery_info.delivery_tag)
  ack_result results_publisher, task_id, timestamp, output_path
ensure
  cleanup_host_parent_path if skip_rm != 1
  force_remove_container
end
