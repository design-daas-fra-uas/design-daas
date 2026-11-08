"""
Entry point of the agent inside an instance: runs the ClientHub (heartbeat
sender + RPC receiver) until the process is stopped. Started as a script
from the agent folder, so its imports are resolved relative to it.
"""

import asyncio
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.join(HERE, "env"))
sys.path.append(os.path.join(HERE, "qmsg"))

# pylint: disable=wrong-import-position,import-error
from hub_instance import QHubConfigInstance, QHubInstance  # noqa: E402

RABBIT_IP = "172.17.0.1"


async def run_client_hub():
    """Starts the ClientHub and keeps it running until cancelled"""
    cfg_hub = QHubConfigInstance(
        rabbitmq_host=RABBIT_IP,
        reconnect_time_client=5,
        reconnect_time_server=5,
        log_topic="daas.inst",
    )
    clienthub = QHubInstance(cfg_hub, setup_logging=True)
    await clienthub.start()
    try:
        while True:
            await asyncio.sleep(1)
    finally:
        await clienthub.stop()


if __name__ == "__main__":
    try:
        asyncio.run(run_client_hub())
    except KeyboardInterrupt:
        pass
    # pika threads may still run; leave without waiting for them
    os._exit(0)
