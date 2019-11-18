
# Deployment steps

* Clone the repo.

* Create `.env` file with the following variables and required values:

```env
RABBITMQ_HOSTNAME=192.254.254.254
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
EXCHANGE_NAME=x_assessment
DURABLE_QUEUE_NAME=q_csharp
BINDING_KEYS=csharp
DEFAULT_BINDING_KEY=default_env
```

* Configure your machine to add an alias IP address to en0 (or whatever network device you are using) as the value specified to the key `RABBITMQ_HOSTNAME` in the .env file before. On MacOS, you can use: `sudo ifconfig en0 alias 192.254.254.254 255.255.255.0`

* Run RabbitMQ server:

`docker run -d --hostname my-rabbit --name some-rabbit -p 5672:5672 -p 15672:15672 rabbitmq:3`

* Enable RabbitMQ management plugin:

`docker exec -t some-rabbit rabbitmq-plugins enable rabbitmq_management`



TBC