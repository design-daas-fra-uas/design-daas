"""Info Backend"""

from app.daas.common.enums import BackendName
from app.daas.resources.info.config import SysteminfoConfig
from app.daas.resources.info.sysinfo import Systeminfo
from app.qweb.service.service_context import QwebBackend


class InfoBackend(QwebBackend):
    """Info backend"""

    component: Systeminfo

    def __init__(self, cfg: SysteminfoConfig):
        self.cfg = cfg
        self.component = Systeminfo(cfg)
        QwebBackend.__init__(
            self, name=BackendName.INFO.value, component=self.component
        )

    async def connect(self) -> bool:
        """Connects adapter"""
        if self.component is not None:
            await self.component.initialize()
            return True
        return False

    async def disconnect(self) -> bool:
        """Disconnects adapter"""
        if self.component is not None:
            self.connected = False
            return True
        return False
