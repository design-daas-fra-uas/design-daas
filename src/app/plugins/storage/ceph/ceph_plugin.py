"""Ceph plugin"""

from app.daas.common.enums import ConfigFile, ConfigSections
from app.daas.storage.ceph.ceph_config import CephstoreConfig
from app.plugins.storage.ceph.ceph_backend import CephBackend
from app.qweb.service.service_plugin import LoadOrder, PluginBase


class CephPlugin(PluginBase):
    """Ceph plugin"""

    def __init__(
        self,
    ):
        cfgfile_db = self.read_toml_file(ConfigFile.CEPH)
        self.cfg_storage = CephstoreConfig(
            **cfgfile_db[ConfigSections.CEPH_STORE.value]
        )
        self.backend = CephBackend(self.cfg_storage)
        self.systasks = []
        self.apitasks = []
        self.handlers = []
        super().__init__(
            LoadOrder.Storage,
            backends=[self.backend],
            handlers=self.handlers,
            systasks=self.systasks,
            apitasks=self.apitasks,
        )
