"""Host plugin"""

from app.daas.adapter.adapter_ssh import SshAdapterConfig
from app.daas.common.enums import ConfigFile, ConfigSections
from app.daas.node.nodecontrol import NodeControllerConfig
from app.plugins.platform.node.node_backend import NodeBackend
from app.plugins.platform.node.node_routes import handler
from app.plugins.platform.node.node_tasks import (
    NodeTask,
    configure_dhcp,
    configure_iptables,
    invoke_upload,
)
from app.qweb.service.service_plugin import LoadOrder, PluginBase


class NodePlugin(PluginBase):
    """Host plugin"""

    def __init__(
        self,
    ):
        cfgfile_db = self.read_toml_file(ConfigFile.NODE)
        self.cfg_ssh = SshAdapterConfig(**cfgfile_db[ConfigSections.HOST_SSH.value])
        # One MAC prefix for Proxmox and dnsmasq: both must match
        prefixmac = self.read_toml_file(ConfigFile.VM)[ConfigSections.VM_API.value][
            "prefixmac"
        ]
        self.cfg_dns = NodeControllerConfig(
            prefixmac=prefixmac, **cfgfile_db[ConfigSections.HOST_DNS.value]
        )
        self.backend = NodeBackend(self.cfg_dns, self.cfg_ssh)
        self.systasks = []
        self.apitasks = [
            (NodeTask.NODE_CONFIGURE_DHCP.value, configure_dhcp),
            (NodeTask.NODE_CONFIGURE_IPTABLES.value, configure_iptables),
            (NodeTask.NODE_INVOKE_UPLOAD.value, invoke_upload),
        ]
        self.handlers = [handler]
        super().__init__(
            LoadOrder.Platform,
            backends=[self.backend],
            handlers=self.handlers,
            systasks=self.systasks,
            apitasks=self.apitasks,
        )
