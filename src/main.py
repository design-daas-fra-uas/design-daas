"""Default app"""

import asyncio
import logging
from app.plugins.platform.extensions.extensions_plugin import ExtensionsPlugin
from app.plugins.resources.admin.admin_plugin import AdminPlugin
from app.qweb.common.config import QwebConfig
from app.qweb.logging.logging import LogTarget
from app.qweb.service.service_runtime import get_qweb_runtime
from app.plugins.common.common import PluginCollection
from app.plugins.core.auth.auth_plugin import AuthPlugin
from app.plugins.core.db.db_plugin import DatabasePlugin
from app.plugins.core.task.task_plugin import TaskPlugin
from app.plugins.platform.container.container_plugin import ContainerPlugin
from app.plugins.platform.instances.inst_plugin import InstancePlugin
from app.plugins.platform.messaging.messaging_plugin import MessagingPlugin
from app.plugins.platform.node.node_plugin import NodePlugin
from app.plugins.platform.phases.phases_plugin import PhasesPlugin
from app.plugins.platform.proxy.proxy_plugin import ProxyPlugin
from app.plugins.platform.vm.vm_plugin import VmPlugin
from app.plugins.resources.info.info_plugin import InfoPlugin
from app.plugins.resources.limits.limits_plugin import LimitPlugin
from app.plugins.storage.ceph.ceph_plugin import CephPlugin
from app.plugins.storage.files.file_plugin import FilePlugin
from app.plugins.testing.test_plugin import TestPlugin


async def _load_plugins(cfg: QwebConfig) -> PluginCollection:
    col = PluginCollection(
        [
            AuthPlugin(),
            DatabasePlugin(),
            NodePlugin(),
            TestPlugin(),
            ContainerPlugin(),
            VmPlugin(),
            FilePlugin(),
            CephPlugin(),
            MessagingPlugin(),
            InfoPlugin(),
            LimitPlugin(),
            ProxyPlugin(),
            TaskPlugin(),
            PhasesPlugin(),
            InstancePlugin(),
            AdminPlugin(),
            ExtensionsPlugin(),
        ],
        cfg.handler.enable_testing,
    )
    _log("Register plugins")
    await col.register_plugins()
    _log("Start plugins")
    await col.start_plugins()
    return col


def _log(msg: str):
    logging.getLogger(LogTarget.RUNTIME.value).info(msg)


async def _run_blocking():
    # Also sets up logging (config/logging.toml)
    runtime_qweb = get_qweb_runtime(qwebfile="config/qweb.toml")
    cfg = runtime_qweb.cfg_qweb
    _log("Load plugins")
    await _load_plugins(cfg)
    _log("Start runtime")
    await runtime_qweb.start()
    _log("Stop backends")
    await runtime_qweb.stop_backends()
    _log("Stop tasks")
    await runtime_qweb.stop_tasks()


if __name__ == "__main__":
    try:
        asyncio.run(_run_blocking())
    except Exception:
        # Before logging is set up, logging still prints errors to stderr
        logging.getLogger(LogTarget.RUNTIME.value).exception("Backend stopped")
