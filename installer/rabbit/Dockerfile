# RabbitMQ broker between the DaaS backend and the agents in the instances
# (see README.md). The DaaS backend starts it as daas-0-rabbit on its start
# (src/config/container.toml), bound to 172.17.0.1 (docker0).

# 3.13: the last 3.x release, the version this setup runs with
FROM rabbitmq:3.13

COPY rabbitmq.conf /etc/rabbitmq/rabbitmq.conf
