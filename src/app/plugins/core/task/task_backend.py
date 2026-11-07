"""Task Backend"""

from app.daas.common.enums import BackendName
from app.qweb.service.service_context import QwebBackend


class TaskBackend(QwebBackend):
    """Task backend"""

    component: dict

    def __init__(self):
        self.component = {}
        QwebBackend.__init__(
            self, name=BackendName.TASK.value, component=self.component
        )
