"""Resource limit Backend"""

from app.daas.common.enums import BackendName
from app.qweb.service.service_context import QwebBackend
from app.daas.resources.limits.ressource_limits import (
    RessourceLimits,
    RessourceLimitsConfig,
)


class LimitBackend(QwebBackend):
    """Resource limit backend"""

    cfg: RessourceLimitsConfig
    component: RessourceLimits

    def __init__(self, cfg_limit: RessourceLimitsConfig):
        self.cfg_limit = cfg_limit
        self.component = RessourceLimits(self.cfg_limit)
        QwebBackend.__init__(
            self, name=BackendName.LIMITS.value, component=self.component
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
