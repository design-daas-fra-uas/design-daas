# rabbit: message broker

RabbitMQ, the message broker between the **DaaS backend** and the **DaaS
agent** inside every instance (container instances and VMs). The backend
sends requests (start an app, set the resolution, mount a folder, ...)
through it and gets the answers back; the agents send heartbeats through it
so the backend knows which instances are alive.

## What is in the image

The official `rabbitmq:3.13` image (the last 3.x release) plus
`rabbitmq.conf` with one setting:

- `heartbeat = 3`: broker and clients check each other every 3 seconds
  (RabbitMQ default: 60), so a dead instance agent is noticed after ~6s.

Everything else is the image default: user `guest` / password `guest`,
which the official image allows from any address (needed: the agents
connect from their container IPs, not from localhost).

## How it is used

- Container **`daas-0-rabbit`** from image **`daas-0-rabbit`**.
- The **DaaS backend starts it** on its own start and stops it on its stop
  (`[service_containers]` in `src/config/container.toml`), with 2 CPUs and
  2 GiB memory.
- Port `5672` (AMQP, what the backend and the agents use), bound to
  `172.17.0.1` (the docker0 bridge address), so only the host and the
  containers reach it, not the network outside. (`4369`, epmd for
  RabbitMQ clustering, is not published: DaaS runs a single broker.)
- The agents connect to `172.17.0.1:5672` (`rabbit_ip` in
  `src/app/daas/messaging/runner_instance.py`), the backend too
  (`rabbitmq_host` in `src/config/messaging.toml`).
- Each agent consumes a queue named after its IP (e.g. `172.17.0.6`), the
  backend sends RPC requests there.
- No volume: queues and messages are not kept when the container stops.
  That is fine, all of them are short-lived.

## Commands

From `installer/` (normal use):

```bash
make rabbit-install     # build the image; a running daas-0-rabbit is restarted from it
make rabbit-status      # running / stopped / not installed
make rabbit-logs        # follow the broker log
make rabbit-restart     # restart the container (agents and backend reconnect)
make rabbit-stop | rabbit-start
make rabbit-reinstall   # delete + build + start
make rabbit-delete      # stop it and remove the image
```

Restarting the broker drops every connection for a few seconds; the agents
and the backend reconnect by themselves.

From `installer/rabbit/` (working on the image itself), as root:

| Command | What it does |
|---|---|
| `make build` | Builds `daas-0-rabbit`. A running container keeps the old image until it is restarted |
| `make check` | Starts a test container `daas-0-rabbit-test` without published ports (does not clash with the running broker), checks it is up, `heartbeat = 3`, the `guest` login from other hosts and that port 5672 speaks AMQP. Removes it again |
| `make clean` | Removes the image |

Look inside the running broker:

```bash
docker exec daas-0-rabbit rabbitmqctl list_queues name messages consumers
docker exec daas-0-rabbit rabbitmqctl list_connections user peer_host state
```

## Things to know

- **Security**: `guest`/`guest` with access from every address. That is
  acceptable only because the ports are bound to `172.17.0.1`; never
  publish them on a public address.
- The backend opens a new AMQP connection for every RPC call to an
  instance (`hub_backend.py`), about 5 per second on a running system.
  It works, but fills the broker log with connect/close lines.

## Files

| File | Content |
|---|---|
| `Dockerfile` | `rabbitmq:3.13` + `rabbitmq.conf` |
| `rabbitmq.conf` | `heartbeat = 3` |
| `check.bash` | Smoke test behind `make check` |
| `Makefile` | build, check, clean |
