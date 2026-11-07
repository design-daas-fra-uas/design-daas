"""VM Blueprints"""

from app.daas.common.enums import BackendName, LayerName
from app.plugins.resources.limits.limits_layer import LimitObject
from app.plugins.resources.limits.limits_tasks import LimitTask
from app.qweb.blueprints.blueprint_info import (
    AuthenticationMode,
    ConcurrencyMode,
    BlueprintInfo,
)
from app.qweb.processing.processor import ApiProcessorAction, ProcessorType
from quart import Blueprint
from app.qweb.blueprints.blueprint_handler import BlueprintHandler
from app.qweb.service.service_context import LayerObject

perf_args = ["counter", "timestamp"]
backends = [BackendName.LIMITS.value, BackendName.DB.value]

infos = [
    BlueprintInfo(
        endpoint_id=130000,
        name="limits_get",
        description="Returns specified limit",
        url="/limits/get_limit",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        conc_params=ConcurrencyMode.CTX_AND_AUTH,
        processor=ProcessorType.API,
        processor_action=ApiProcessorAction.JSON,
        processor_task=LimitTask.LIMIT_GET.value,
        content_type="application/json",
        request_args_mandatory=["id_owner"],
        request_args_optional=[],
        request_args_common=perf_args,
        backends=backends,
        objects=[
            LayerObject(
                "entity", LimitObject.BYOWNER.value, LayerName.LIMIT.value
            )
        ],
    ),
    BlueprintInfo(
        endpoint_id=130001,
        name="limits_put",
        description="Stores specified limit",
        url="/limits/put_limit",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        admin_only=True,
        conc_params=ConcurrencyMode.CTX_AND_AUTH,
        processor=ProcessorType.API,
        processor_action=ApiProcessorAction.JSON,
        processor_task=LimitTask.LIMIT_PUT.value,
        content_type="application/json",
        request_args_mandatory=[
            "id_owner",
            "vm_max",
            "container_max",
            "obj_max",
            "cpu_max",
            "mem_max",
            "dsk_max",
        ],
        request_args_optional=[],
        request_args_common=perf_args,
        backends=backends,
        objects=[
            LayerObject(
                "entity", LimitObject.BYOWNER.value, LayerName.LIMIT.value
            )
        ],
    ),
    BlueprintInfo(
        endpoint_id=130002,
        name="limits_remove",
        description="Removes specified limit",
        url="/limits/remove_limit",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        admin_only=True,
        conc_params=ConcurrencyMode.CTX_AND_AUTH,
        processor=ProcessorType.API,
        processor_action=ApiProcessorAction.JSON,
        processor_task=LimitTask.LIMIT_REMOVE.value,
        content_type="application/json",
        request_args_mandatory=["id_owner"],
        request_args_optional=[],
        request_args_common=perf_args,
        backends=backends,
        objects=[
            LayerObject(
                "entity", LimitObject.BYOWNER.value, LayerName.LIMIT.value
            )
        ],
    ),
    BlueprintInfo(
        endpoint_id=130003,
        name="limits_list",
        description="Lists specified limit",
        url="/limits/list_limits",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        admin_only=True,
        conc_params=ConcurrencyMode.CTX_AND_AUTH,
        processor=ProcessorType.API,
        processor_action=ApiProcessorAction.JSON,
        processor_task=LimitTask.LIMIT_LIST.value,
        content_type="application/json",
        request_args_mandatory=[],
        request_args_optional=[],
        request_args_common=perf_args,
        backends=backends,
        objects=[
            LayerObject("entity", LimitObject.LIST.value, LayerName.LIMIT.value)
        ],
    ),
]


handler = BlueprintHandler(
    blueprints=Blueprint("routes_limits", __name__),
    infos=infos,
)
