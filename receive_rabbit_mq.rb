require "bunny"
require "json"
require "zip"
require "pathname"

class ClientException < RuntimeError
  attr_reader :status

  def initialize(status = 400, message)
    puts "Client error: #{message.to_s}, #{status}"
    @status = status
    super(message)
  end
end

class ServerException < RuntimeError
  attr_reader :status

  def initialize(status = 500, message)
    puts "Server error: #{message.to_s}, #{status}"
    @status = status
    super(message)
  end
end

def client_error!(message, status, _headers = {}, _backtrace = [])
  raise ClientException.new status, message
end

def server_error!(message, status, _headers = {}, _backtrace = [])
  raise ServerException.new status, message
end

class Receiver
  def default_return(value)
    { message: value ||= "" }
  end

  def valid_zip?(file)
    zip = Zip::File.open(file)
    true
  rescue StandardError
    false
  ensure
    zip.close if zip
  end

  # Flat extract a zip file, no sub-directories.
  def extract_zip(input_zip_file_path, output_loc)
    Zip::File.open(input_zip_file_path) do |zip_file|
      # Handle entries one by one
      zip_file.each do |entry|
        # Extract to file/directory/symlink
        puts "Extracting #{entry.name} #{entry.ftype}"
        pn = Pathname.new entry.name
        entry.extract "#{output_loc}/#{pn.basename}" unless entry.ftype.to_s == "directory"
      end
      # # Find specific entry
      # entry = zip_file.glob('*.csv').first
      # puts entry.get_input_stream.read
    end
  end

  def get_project_path(project_id)
    "student_projects/project_#{project_id}"
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
    rpath = "#{path}/run.sh"
    server_error!({ error: "File #{rpath} doesn't exist" }, 500) unless File.exists? rpath
    result = {}
    `chmod +x #{rpath}`
    # `cd #{path}`
    Dir.chdir path do
      result = { run_result: `./run.sh` }
    end
    result
  end

  # Step 4
  def cleanup_after_your_own_mess(path)
    if File.exists? path
      puts "Recursively force removing: " + path
      FileUtils.rm_rf path
    end
  end

  ##################################################################
  ##################################################################

  def start
    connection = Bunny.new(hostname: ENV['RABBITMQ_HOSTNAME'] || 'localhost', username: "guest", password: "guest")
    connection.start

    channel = connection.create_channel
    exchange = channel.topic('asssessment', :durable => true)
    #channel.prefetch(1) # Use this for making rabbitMQ not give a worker more than 1 jobs if it is already working on one.

    queue = channel.queue(ENV['ROUTE_KEY'], durable: true)
    

    language_environments = ENV['LANGUAGE_ENVIRONMENTS'].split(',')
    language_environments.each do |language_environment| # language_environments can be something like "#.csharp" "#.splashkit.csharp" "#.python", etc.
      queue.bind(exchange, routing_key: language_environment)
    end
    queue.bind(exchange, routing_key: ENV['DEFAULT_LANGUAGE_ENVIRONMENT']) unless ENV['DEFAULT_LANGUAGE_ENVIRONMENT'].nil?

    begin
      puts " [*] Waiting for messages. To exit press CTRL+C"
      queue.subscribe(manual_ack: true, block: true) do |delivery_info, _properties, params|
        params = JSON.parse(params)
        puts params

        client_error!({ error: "Invalid zip file: #{params["submission"]}" }, 400) unless valid_zip? params["submission"]
        client_error!({ error: "Invalid zip file: #{params["assessment"]}" }, 400) unless valid_zip? params["assessment"]
        output_loc = get_project_path params[:project_id]
        FileUtils.mkdir_p output_loc
        skip_rm = params[:skip_rm] || 0

        begin
          extract_submission params["submission"], output_loc
          extract_assessment params["assessment"], output_loc

          result = run_assessment_script output_loc
          puts result

          channel.ack(delivery_info.delivery_tag)
        rescue ClientException => e
          client_error!({ error: e.message }, e.status)
        rescue ServerException
          if skip_rm != 1
            cleanup_after_your_own_mess output_loc
          end
          server_error!({ error: "Internal server error" }, 500)
        rescue
          if skip_rm != 1
            cleanup_after_your_own_mess output_loc
          end
          server_error!({ error: "Internal server error" }, 500)
        else
          if skip_rm != 1
            cleanup_after_your_own_mess output_loc
          end

          default_return result
          channel.ack(delivery_info.delivery_tag)
        end # End inner begin

      end
    rescue Interrupt => _
      connection.close

      exit(0)
    end # End outer begin
  end
end
