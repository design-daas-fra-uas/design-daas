"""Messaging plugin"""

from app.daas.adapter.adapter_ssh import SshAdapterConfig
from app.daas.common.config import InstanceControllerConfig
from app.daas.common.enums import ConfigFile, ConfigSections
from app.daas.messaging.qmsg.hub_backend import QHubConfigBackend
from app.plugins.platform.messaging.messaging_backend import MessagingBackend
from app.qweb.service.service_plugin import LoadOrder, PluginBase


class MessagingPlugin(PluginBase):
    """Messaging plugin"""

    def __init__(self):
        cfgfile_db = self.read_toml_file(ConfigFile.MESSAGING)
        self.cfg_main = InstanceControllerConfig(
            **cfgfile_db[ConfigSections.MESSAGING.value]
        )
        self.cfg_queue = QHubConfigBackend(
            **cfgfile_db[ConfigSections.MESSAGING_QUEUE.value]
        )
        self.cfg_ssh = SshAdapterConfig(
            **cfgfile_db[ConfigSections.MESSAGING_SSH.value]
        )
        self.backend = MessagingBackend(self.cfg_main, self.cfg_queue, self.cfg_ssh)
        self.systasks = []
        self.apitasks = []
        self.handlers = []
        super().__init__(
            LoadOrder.Platform,
            backends=[self.backend],
            handlers=self.handlers,
            systasks=self.systasks,
            apitasks=self.apitasks,
        )
