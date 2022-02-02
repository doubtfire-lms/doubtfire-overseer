
# Deployment steps

* Clone the repo.

* Create `.env` file with the following variables and required values:

  ```env
  RABBITMQ_HOSTNAME=192.254.254.254
  RABBITMQ_USERNAME=guest
  RABBITMQ_PASSWORD=guest

  HOST_XFS_VOLUME=/some/path
  CONTAINER_NAME=Some-Docker-Container-Name
  ```

  * `RABBITMQ_HOSTNAME`, `RABBITMQ_USERNAME`, and `RABBITMQ_PASSWORD` provide details needed to access the rabbitmq.
  * `HOST_XFS_VOLUME` is a path on the host that will run the automated code. This needs to refer to the location where overseer containers will store their work. Overseer uses this to setup a volume in each container it creates. When multiple overseer instances are run this path needs to be unique for each instance. Overseer will create `sandbox` and `output` folders in this location.
  * `CONTAINER_NAME` is optional (defaults to `overseer-container`) and provides the name of the container that overseer creates. If there are multiple overseer instances then they must have unique container names.

* Easiest option is to setup rabbitmq alongside overseer in the same docker network, and have it setup to run with the management interface.
  
* Alternatively:
  * Configure your machine to add an alias IP address to en0 (or whatever network device you are using) as the value specified to the key `RABBITMQ_HOSTNAME` in the .env file before. On MacOS, you can use: `sudo ifconfig en0 alias 192.254.254.254 255.255.255.0`
  * Run RabbitMQ server:

    `docker run -d --hostname my-rabbit --name some-rabbit -p 5672:5672 -p 15672:15672 rabbitmq:3`

  * Enable RabbitMQ management plugin:

    `docker exec -t some-rabbit rabbitmq-plugins enable rabbitmq_management`

* Run overseer using:
    `bundle exec ruby ./app.rb`

# Basic operation

* When overseer starts is listens to the **q.tasks** queue on the **ontrack** exchange of the rabbitmq and awaits any messages marked as **task.submission**. When a submission is received the message triggers action in overseer.
* Params received include:
  * `output_path`: where to store automated assessment results
  * `submission`: the path to the submission zip file or folder
  * `assessment`: the path to the submission assessment resources
  * `timestamp`: the time of the submission
  * `task_id`: the task associated with the submission
  * `overseer_assessment_id`: the overseer assessment id
  * `docker_image_name_tag`: the tag of the docker image to run the scripts within
* Overseer starts by unpacking the submission along with the assessment resources to the working directory. Files in the assessment resources will override those in the submission if needed.
* Once the files are in place Overseer starts a container with the indicated `CONTAINER_NAME` using the image details from the assessment resources and runs two scripts: `build.sh` is run and if the result is 0 it runs `run.sh`.
  * Anything written to standard output and standard error from these scripts will be collected in the output message for the task.
  * Each of these scripts is passed a path to a yaml file where comment and status changes are stored.
  * `build.sh` should write messages to the `build_message` key in the yaml file.
  * `run.sh` should write messages to the `run_message` key in the yaml file.
  * Both build and run scripts can write a new status to `new_status`.
  * The exit status of the build and run steps is appended to the output text collected from standard out.
* When both scripts have been run, a message is returned to Doubtfire/OnTrack using the `overseer.result` routing key to the `q.overseer` of the `ontrack` exchange. This contains the task id, timestamp, and overseer assessment id. The output text and yaml files are also available to OnTrack.
