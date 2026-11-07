"""Admin Backend"""

from app.daas.common.enums import BackendName
from app.qweb.service.service_context import QwebBackend


class AdminBackend(QwebBackend):
    """Admin backend"""

    component: list = []

    def __init__(self):
        QwebBackend.__init__(
            self, name=BackendName.ADMIN.value, component=self.component
        )
