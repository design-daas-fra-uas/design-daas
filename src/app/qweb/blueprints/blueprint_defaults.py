"""Default Blueprints"""

from quart import Blueprint
from app.qweb.blueprints.blueprint_handler import BlueprintHandler
from app.qweb.blueprints.blueprint_info import (
    AuthenticationMode,
    ConcurrencyMode,
    BlueprintInfo,
)
from app.qweb.processing.processor import (
    FileProcessorAction,
    ProcessorType,
    TemplateProcessorAction,
)

infos = [
    BlueprintInfo(
        endpoint_id=10000,
        name="index",
        description="Default Endpoint",
        url="/",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        conc_params=ConcurrencyMode.AUTH_AND_PROC,
        processor=ProcessorType.STATIC_TEMPLATE,
        processor_action=TemplateProcessorAction.STATIC_HTML,
        override_target="layout.html",
        content_type="text/html",
        static_args={"title": "Qweb"},
    ),
    BlueprintInfo(
        endpoint_id=10001,
        name="index_debug",
        description="Default Endpoint",
        url="/debug",
        methods=["POST"],
        auth_params=AuthenticationMode.ALL,
        conc_params=ConcurrencyMode.AUTH_AND_PROC,
        processor=ProcessorType.STATIC_TEMPLATE,
        processor_action=TemplateProcessorAction.STATIC_HTML,
        override_target="layout.html",
        content_type="text/html",
        static_args={"title": "Qweb"},
    ),
    BlueprintInfo(
        endpoint_id=10002,
        name="favicon",
        description="Default Endpoint",
        methods=["GET"],
        url="/favicon.ico",
        auth_params=AuthenticationMode.NONE,
        conc_params=ConcurrencyMode.AUTH_AND_PROC,
        processor=ProcessorType.FILE,
        processor_action=FileProcessorAction.ROOT_FILE,
        content_type="*/*",
    ),
    BlueprintInfo(
        endpoint_id=10003,
        name="robots",
        description="Endpoint for crawlers",
        methods=["GET"],
        url="/robots.txt",
        auth_params=AuthenticationMode.NONE,
        conc_params=ConcurrencyMode.AUTH_AND_PROC,
        processor=ProcessorType.FILE,
        processor_action=FileProcessorAction.ROOT_FILE,
        content_type="text/html",
    ),
]
handler = BlueprintHandler(
    blueprints=Blueprint("routes_default", __name__),
    infos=infos,
)
