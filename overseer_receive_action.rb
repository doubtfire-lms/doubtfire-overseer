# frozen_string_literal: true

require 'zip'
require 'securerandom'
require 'yaml'

# CONSTANTS. Will never change.
# Start ==========================================================

module CONSTANTS
  RUN              = 'run'
  BUILD            = 'build'

  # Mounted as a volume
  DOCKER_WORKDIR   = 'home/overseer/work-dir'
  DOCKER_OUTDIR    = 'home/overseer/work-dir/output'
  DOCKER_EXECDIR   = 'home/overseer/work-dir/sandbox'
end

def docker_workdir_path
  "/#{CONSTANTS::DOCKER_WORKDIR}"
end

def docker_outdir_path
  "/#{CONSTANTS::DOCKER_OUTDIR}"
end

def docker_execdir_path
  "/#{CONSTANTS::DOCKER_EXECDIR}"
end

# End ==========================================================


# ENV CONSTANTS. Will change for different overseer instances.
# Start ==========================================================

# Used by execution container to specify host volume.
def host_xfs_volume_path
  # Root path of the directory on the HOST used as a volume for
  # temporarily storing files generated by Docker command
  # execution. Should be mounted as a XFS volume.
  ENV['HOST_XFS_VOLUME']
end

# Used by execution container to specify host volume.
def host_exec_path
  # Docker volumes needs absolute source and destination paths
  "#{host_xfs_volume_path}/sandbox"
end

# Used by execution container to specify host volume.
def host_output_path
  # Docker volumes needs absolute source and destination paths
  "#{host_xfs_volume_path}/output"
end

def container_name
  ENV['CONTAINER_NAME'] || 'overseer-container'
end

# End ==========================================================

def ack_result(results_publisher, overseer_assessment_id, task_id, timestamp, output_path)
  return if results_publisher.nil?

  msg = { overseer_assessment_id: overseer_assessment_id, task_id: task_id, timestamp: timestamp }

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

# Extract the zip file with all path details, or flatten based on parameters. Allows details to be overriden or not depending on parameters passed in.
def extract_zip(input_zip_file_path, output_loc, flatten = false, override = false)
  puts "Extracting:"
  puts "  zip file:".ljust(20) + input_zip_file_path
  puts "  to:".ljust(20) + output_loc
  puts "  files: "
  Zip::File.open(input_zip_file_path) do |zip_file|
    # Handle entries one by one
    zip_file.each do |entry|
      # Extract to file/directory/symlink
      unless entry.ftype.to_s == 'directory'
        if flatten
          pn = File.join(output_loc, Pathname.new(entry.name).basename)
        else
          pn = File.join(output_loc, entry.name)
        end
        override_msg = ''
        if File.exist?(pn)
          if override
            FileUtils.rm_f(pn)
            override_msg = ' OVERIDE'
          else
            puts "    - type: #{entry.ftype}".ljust(20) + " original_name: #{entry.name}".ljust(50) + " SKIPPED"
            # dont override so skip
            continue
          end
        end
        FileUtils.mkdir_p(File.dirname(pn))
        puts "    - type: #{entry.ftype}".ljust(20) + " original_name: #{entry.name}".ljust(50) + " final_name: #{pn}#{override_msg}"
        entry.extract pn
      end
    end
  end
end

def force_remove_container
  puts "Removing container forcibly: #{container_name}"
  `docker container rm -vf #{container_name}`
end

##################################################################
##################################################################

# Step 3
# Fire up a docker container to perform an execution step.
# output_path:      Destination path to write files to. This will be a OnTrack FS path.
# random_string:    Prefix for .yaml and .txt files that are to be copied.
# exec_mode:        Can either be CONSTANTS::BUILD OR CONSTANTS::RUN.
# command:          The bash command to be run via
#                   `docker run [options] <image_name_tag> /bin/bash -c "#{command}"`.
# image_name_tag:   Name and tag of the image to be run as a container.
def run_assessment_script_via_docker(output_path, random_string, exec_mode, command, image_name_tag, task_id, timestamp, overseer_assessment_id)
  client_error!({ error: "A valid Docker image_name:tag is needed" }, 400) if image_name_tag.nil? || image_name_tag.to_s.strip.empty?
  force_remove_container

  puts 'Running assessment container with the following configuration:'
  puts "  container_name: #{container_name}"
  puts "  image_name_tag: #{image_name_tag}"
  puts '  volumes:'
  puts "    - #{host_exec_path}:/#{CONSTANTS::DOCKER_EXECDIR}"
  puts "    - #{host_output_path}:/#{CONSTANTS::DOCKER_OUTDIR}"

  puts "ππππππππππππππππ Container '#{container_name}' execution for exec_mode: '#{exec_mode}' STARTED ππππππππππππππππππππ"
  puts 'π' * 120
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

  # puts "docker run \
  # -m 100MB \
  # --memory-swap 100MB \
  # --restart no \
  # --cpus 1 \
  # --network none \
  # --volume #{host_exec_path}:/#{CONSTANTS::DOCKER_EXECDIR} \
  # --volume #{host_output_path}:/#{CONSTANTS::DOCKER_OUTDIR} \
  # --name #{container_name} \
  # #{image_name_tag} \
  # /bin/bash -c \"#{command}\""

  `timeout 300 docker run \
  --restart no \
  --cpus 1 \
  --network none \
  --volume #{host_exec_path}:/#{CONSTANTS::DOCKER_EXECDIR} \
  --volume #{host_output_path}:/#{CONSTANTS::DOCKER_OUTDIR} \
  --name #{container_name} \
  #{image_name_tag} \
  /bin/bash -c "#{command}"`

  puts 'π' * 120
  puts "ππππππππππππππππ Container '#{container_name}' execution for exec_mode: '#{exec_mode}' ENDED ππππππππππππππππππππππ"

  exitstatus = $?.exitstatus
  extract_result_files docker_outdir_path, output_path, random_string, exitstatus

  diff_result = `docker diff #{container_name}`
  extract_docker_diff_file output_path, diff_result, exec_mode

  puts "Docker run command execution status code: #{exitstatus}"

  # if exitstatus != 0
  #   result = {}
  #   result[:task_id] = task_id
  #   result[:overseer_assessment_id] = overseer_assessment_id
  #   result[:timestamp] = timestamp
  #   raise Subscriber::ServerException.new result, 500
  # end

  exitstatus
end

# Step 4
# Copy the results of docker execution saved at a HOST volume to OnTrack FS.
# s_path:           Source path on HOST to read files from.
# output_path:      Destination path to write files to. This will be a OnTrack FS path.
# random_string:    Prefix for .yaml and .txt files that are to be copied.
# exitstatus:       Exist status of the last `docker run` command.
def extract_result_files(s_path, output_path, random_string, exitstatus)
  client_error!({ error: "A valid output_path is needed" }, 400) if output_path.nil? || output_path.to_s.strip.empty?

  puts 'Extracting result file from the sandbox:'
  puts "  source:".ljust(20) + s_path
  puts "  destination:".ljust(20) + output_path
  puts "  file prefix:".ljust(20) + random_string

  # Get path to output files
  output_txt_file_name = "#{output_path}/output.txt"
  output_yaml_file_name = "#{output_path}/output.yaml"

  # Set files to input into the scripts
  input_txt_file_name = "#{s_path}/#{random_string}.txt"
  input_yaml_file_name = "#{s_path}/#{random_string}.yaml"

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
      `chmod o+w #{output_txt_file_name}`
    end

    # FileUtils.rm input_txt_file_name
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
      `chmod o+w #{output_yaml_file_name}`
    end

    # FileUtils.rm input_yaml_file_name
  else
    puts "Results file: #{s_path}/#{random_string}.yaml does not exist"
  end

end

# Step 5
# Write the results of `docker diff` to OnTrack FS.
# output_path:      Destination path to write files to. This will be a OnTrack FS path.
# diff_result:      String result of `docker diff <container_name>`.
# exec_mode:        Can either be CONSTANTS::BUILD OR CONSTANTS::RUN.
def extract_docker_diff_file(output_path, diff_result, exec_mode)
  File.write("#{output_path}/#{exec_mode}-diff.txt", "docker diff: \n#{!diff_result&.strip&.empty? ? diff_result : 'nothing changed' }")
end

# Step 0, 6
def cleanup_docker_workdir
  return if docker_workdir_path.nil?
  return unless docker_workdir_path.strip.empty? # not nil or empty
  return unless File.exist? docker_workdir_path

  puts "Cleaning HOST_XFS_VOLUME force-recursively: #{docker_workdir_path}/*"
  FileUtils.rm_rf(Dir.glob("#{docker_workdir_path}/*"))
end

def valid_zip_file_param?(params)
  !params['zip_file'].nil? && params['zip_file'].is_a?(Integer) && params['zip_file'] == 1
end

def receive(subscriber_instance, channel, results_publisher, delivery_info, _properties, params)
  puts "*" * 120
  puts "*" * 120
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

  puts "params: #{JSON.pretty_generate(params)}"

  docker_image_name_tag = params['docker_image_name_tag']
  output_path = params['output_path']
  submission = params['submission']
  assessment = params['assessment']
  timestamp = params['timestamp']
  task_id = params['task_id']
  overseer_assessment_id = params['overseer_assessment_id']

  unless task_id.is_a?(Integer)
    subscriber_instance.client_error!({ error: "Invalid task_id: #{task_id}" }, 400)
  end

  unless overseer_assessment_id.is_a?(Integer)
    subscriber_instance.client_error!({ error: "Invalid overseer_assessment_id: #{overseer_assessment_id}" }, 400)
  end

  unless File.exist? submission
    if valid_zip_file_param? params
      subscriber_instance.client_error!({ error: "Zip file not found: #{submission}", overseer_assessment_id: overseer_assessment_id, task_id: task_id, timestamp: timestamp }, 400)
    else
      # By default, Overseer will expect a folder path
      subscriber_instance.client_error!({ error: "Folder not found: #{submission}", overseer_assessment_id: overseer_assessment_id, task_id: task_id, timestamp: timestamp }, 400)
    end
  end

  unless File.exist? assessment
    subscriber_instance.client_error!({ error: "Zip file not found: #{assessment}", overseer_assessment_id: overseer_assessment_id, task_id: task_id, timestamp: timestamp }, 400)
  end

  unless valid_zip? submission
    subscriber_instance.client_error!({ error: "Invalid zip file: #{submission}", overseer_assessment_id: overseer_assessment_id, task_id: task_id, timestamp: timestamp }, 400)
  end

  unless valid_zip? assessment
    subscriber_instance.client_error!({ error: "Invalid zip file: #{assessment}", overseer_assessment_id: overseer_assessment_id, task_id: task_id, timestamp: timestamp }, 400)
  end

  if File.exist? docker_workdir_path
    cleanup_docker_workdir
  end

  if File.exist? docker_execdir_path
    FileUtils.rm_rf docker_execdir_path
  end

  if File.exist? docker_outdir_path
    FileUtils.rm_rf docker_outdir_path
  end

  # TODO: Add correct permissions here
  FileUtils.mkdir_p docker_execdir_path
  FileUtils.mkdir_p docker_outdir_path

  # Clean any output txt and yaml if present
  FileUtils.mkdir_p(output_path) unless File.exist?(output_path)
  FileUtils.rm("#{output_path}/output.txt") if File.exist?("#{output_path}/output.txt")
  FileUtils.rm("#{output_path}/output.yaml") if File.exist?("#{output_path}/output.yaml")

  
  skip_rm = params['skip_rm'] || 0

  # Step 1
  if valid_zip_file_param? params
    # Flatten to ensure submission files are within the root folder not in a task id based subfolder
    extract_zip submission, docker_execdir_path, true, false
  else
    `cp -R #{submission}/. #{docker_execdir_path}`
  end

  # Step 2
  extract_zip assessment, docker_execdir_path, false, true

  random_string = "#{CONSTANTS::BUILD}-#{SecureRandom.hex}"
  exit_code = run_assessment_script_via_docker(
    output_path,
    random_string,
    CONSTANTS::BUILD,
    "chmod u+x /#{CONSTANTS::DOCKER_EXECDIR}/#{CONSTANTS::BUILD}.sh && /#{CONSTANTS::DOCKER_EXECDIR}/#{CONSTANTS::BUILD}.sh /#{CONSTANTS::DOCKER_OUTDIR}/#{random_string}.yaml >> /#{CONSTANTS::DOCKER_OUTDIR}/#{random_string}.txt 2>> /#{CONSTANTS::DOCKER_OUTDIR}/#{random_string}.txt",
    docker_image_name_tag,
    task_id,
    timestamp,
    overseer_assessment_id
  )

  if exit_code == 0
    random_string = "#{CONSTANTS::RUN}-#{SecureRandom.hex}"
    run_assessment_script_via_docker(
      output_path,
      random_string,
      CONSTANTS::RUN,
      "chmod u+x /#{CONSTANTS::DOCKER_EXECDIR}/#{CONSTANTS::RUN}.sh && /#{CONSTANTS::DOCKER_EXECDIR}/#{CONSTANTS::RUN}.sh /#{CONSTANTS::DOCKER_OUTDIR}/#{random_string}.yaml >> /#{CONSTANTS::DOCKER_OUTDIR}/#{random_string}.txt 2>> /#{CONSTANTS::DOCKER_OUTDIR}/#{random_string}.txt",
      docker_image_name_tag,
      task_id,
      timestamp,
      overseer_assessment_id
    )
  end
rescue Subscriber::ClientException => e
  channel.ack(delivery_info.delivery_tag)
  # TODO: Log the error
  puts "Error: #{e.message}"
rescue Subscriber::ServerException => e
  channel.ack(delivery_info.delivery_tag)
  # TODO: Log the error
  puts "Error: #{e.message}"
rescue StandardError => e
  channel.ack(delivery_info.delivery_tag)
  puts "StandardError: #{e.message}"
  subscriber_instance.server_error!({ error: 'Internal server error', overseer_assessment_id: overseer_assessment_id, task_id: task_id, timestamp: timestamp }, 500)
else
  channel.ack(delivery_info.delivery_tag)
  ack_result results_publisher, overseer_assessment_id, task_id, timestamp, output_path
ensure
  if skip_rm != 1
    cleanup_docker_workdir
  else
    puts 'Skipping force removal because skip_rm != 1'
  end
  force_remove_container
end
