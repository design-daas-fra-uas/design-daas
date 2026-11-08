"""
Entry point of the agent inside an instance: runs the ClientHub (heartbeat
sender + RPC receiver) until the process is stopped. Started as a script
from the agent folder, so its imports are resolved relative to it.
"""


async def run_client_hub():
    """Starts the ClientHub and keeps it running until cancelled"""
    cfg_hub = QHubConfigInstance(
        rabbitmq_host=rabbit_ip,
        reconnect_time_client=5,
        reconnect_time_server=5,
        log_topic="daas.inst",
    )
    clienthub = QHubInstance(cfg_hub, setup_logging=True)
    await clienthub.start()
    try:
        while True:
            await asyncio.sleep(1)
    except KeyboardInterrupt:
        os._exit(0)

    await clienthub.stop()
    os._exit(0)


if __name__ == "__main__":
    import os
    import sys

    sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "env")))
    sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "qmsg")))
    import asyncio
    from hub_instance import QHubInstance, QHubConfigInstance

    asyncio.run(run_client_hub())
    os._exit(0)
