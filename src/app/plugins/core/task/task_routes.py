"""Task Routes"""

from quart import Blueprint
from app.daas.common.enums import BackendName, LayerName
from app.plugins.core.task.task_layer import ServiceObject
from app.plugins.core.task.task_tasks import TaskTask
from app.qweb.blueprints.blueprint_handler import BlueprintHandler
from app.qweb.blueprints.blueprint_info import (
    AuthenticationMode,
    ConcurrencyMode,
    BlueprintInfo,
)
from app.qweb.processing.processor import (
    ApiProcessorAction,
    ProcessorType,
)
from app.qweb.service.service_context import LayerObject

perf_args = ["counter", "timestamp"]
backends = [BackendName.DB.value]
infos = [
    BlueprintInfo(
        endpoint_id=100000,
        name="task_get",
        description="Returns specified task",
        url="/tasks/get",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        conc_params=ConcurrencyMode.CTX_AND_AUTH,
        processor=ProcessorType.API,
        processor_action=ApiProcessorAction.JSON,
        processor_task=TaskTask.TASK_GET.value,
        content_type="application/json",
        request_args_mandatory=["id_task"],
        request_args_optional=[],
        request_args_common=perf_args,
        backends=backends,
        objects=[
            LayerObject(
                "entity", ServiceObject.TASK.value, LayerName.TASK.value
            )
        ],
    ),
    BlueprintInfo(
        endpoint_id=100001,
        name="task_stop",
        description="Stops specified task",
        url="/tasks/stop",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        conc_params=ConcurrencyMode.CTX_AND_AUTH,
        processor=ProcessorType.API,
        processor_action=ApiProcessorAction.JSON,
        processor_task=TaskTask.TASK_STOP.value,
        content_type="application/json",
        request_args_mandatory=[],
        request_args_optional=["id_task", "id_object", "id_instance"],
        request_args_common=perf_args,
        backends=backends,
        objects=[
            LayerObject(
                "entity", ServiceObject.TASKFILTER.value, LayerName.TASK.value
            )
        ],
    ),
    BlueprintInfo(
        endpoint_id=100002,
        name="task_list",
        description="Returns specified tasklist",
        url="/tasks/list",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        conc_params=ConcurrencyMode.CTX_AND_AUTH,
        processor=ProcessorType.API,
        processor_action=ApiProcessorAction.JSON,
        processor_task=TaskTask.TASK_LIST.value,
        content_type="application/json",
        request_args_mandatory=["state"],
        request_args_optional=["id_object", "id_instance"],
        request_args_common=perf_args,
        backends=backends,
        objects=[
            LayerObject(
                "entity", ServiceObject.TASKLIST.value, LayerName.TASK.value
            )
        ],
    ),
    BlueprintInfo(
        endpoint_id=100003,
        name="task_status",
        description="Returns status for all tasks",
        url="/tasks/status",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        conc_params=ConcurrencyMode.CTX_AND_AUTH,
        processor=ProcessorType.API,
        processor_action=ApiProcessorAction.JSON,
        processor_task=TaskTask.TASK_STATUS.value,
        content_type="application/json",
        request_args_mandatory=[],
        request_args_optional=[],
        request_args_common=perf_args,
        backends=backends,
        objects=[
            LayerObject(
                "entity", ServiceObject.TASKSTATUS.value, LayerName.TASK.value
            )
        ],
    ),
]


handler = BlueprintHandler(
    blueprints=Blueprint("routes_task", __name__),
    infos=infos,
)
