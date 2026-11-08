"""Test plugin"""

from app.daas.common.enums import BackendName
from app.qweb.service.service_plugin import LoadOrder, PluginBase
from app.plugins.testing.test_tasks import TestTask, test_get_layer_entity
from app.plugins.testing.test_routes import handler
from app.plugins.testing.test_objects import TestBackend, TestObjectLayer


# pylint: disable=too-few-public-methods
class TestPlugin(PluginBase):
    """Testplugin"""

    def __init__(
        self,
    ):
        self.backend = TestBackend()
        self.objlayer = TestObjectLayer(
            name=BackendName.TESTING.value, backend=self.backend
        )
        self.systasks = []
        self.apitasks = [(TestTask.TEST_GET_ENTITY.value, test_get_layer_entity)]
        super().__init__(
            LoadOrder.Storage,
            backends=[self.backend],
            layers=[self.objlayer],
            handlers=[handler],
            systasks=self.systasks,
            apitasks=self.apitasks,
            testing=True,
        )
