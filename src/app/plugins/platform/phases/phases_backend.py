"""Phases Backend"""

from app.daas.common.enums import BackendName
from app.qweb.service.service_context import QwebBackend


class PhasesBackend(QwebBackend):
    """Phases backend"""

    component: dict

    def __init__(self):
        self.component = {}
        QwebBackend.__init__(
            self, name=BackendName.PHASES.value, component=self.component
        )
