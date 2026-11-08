"""Proxy plugin"""

from app.daas.common.enums import ConfigFile, ConfigSections
from app.daas.proxy.config import ViewerConfig
from app.plugins.platform.proxy.proxy_routes import handler
from app.plugins.platform.proxy.proxy_backend import ProxyBackend
from app.plugins.platform.proxy.proxy_tasks import (
    ProxyTask,
    proxy_ws,
    viewer_check,
    viewer_connect,
    viewer_disconnect,
    viewer_info,
    viewer_set_screen,
    viewer_template,
)
from app.qweb.service.service_plugin import LoadOrder, PluginBase


class ProxyPlugin(PluginBase):
    """Proxy plugin"""

    def __init__(
        self,
    ):
        cfgfile_db = self.read_toml_file(ConfigFile.PROXY)
        self.cfg_proxy = ViewerConfig(**cfgfile_db[ConfigSections.PROXY_VIEWER.value])
        self.backend = ProxyBackend(self.cfg_proxy)
        self.systasks = []
        self.apitasks = [
            (ProxyTask.VIEWER_TEMPLATE.value, viewer_template),
            (ProxyTask.VIEWER_SET_SCREEN.value, viewer_set_screen),
            (ProxyTask.VIEWER_CHECK.value, viewer_check),
            (ProxyTask.VIEWER_INFO.value, viewer_info),
            (ProxyTask.VIEWER_PROXY_WS.value, proxy_ws),
            (ProxyTask.VIEWER_CONNECT.value, viewer_connect),
            (ProxyTask.VIEWER_DISCONNECT.value, viewer_disconnect),
        ]
        self.handlers = [handler]
        super().__init__(
            LoadOrder.Platform,
            backends=[self.backend],
            handlers=self.handlers,
            systasks=self.systasks,
            apitasks=self.apitasks,
        )
