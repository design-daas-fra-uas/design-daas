"""Default Blueprints"""

from quart import Blueprint
from app.daas.common.enums import BackendName
from app.qweb.blueprints.blueprint_handler import BlueprintHandler
from app.qweb.blueprints.blueprint_info import (
    AuthenticationMode,
    ConcurrencyMode,
    BlueprintInfo,
)
from app.qweb.processing.processor import (
    ApiProcessorAction,
    ProcessorType,
    TemplateProcessorAction,
)

test_args = ["counter", "timestamp"]
test_backends = [BackendName.DB.value]
test_methods = ["POST"]
infos = [
    BlueprintInfo(
        endpoint_id=40000,
        name="get_login",
        description="Default Browsertest Endpoint",
        url="/login",
        methods=["GET"],
        auth_params=AuthenticationMode.NONE,
        conc_params=ConcurrencyMode.AUTH_AND_PROC,
        processor=ProcessorType.STATIC_TEMPLATE,
        processor_action=TemplateProcessorAction.STATIC_HTML,
        override_target="login.html",
        content_type="text/html",
        static_args={"title": "Login"},
    ),
    BlueprintInfo(
        endpoint_id=40001,
        name="post_login",
        description="Default Browsertest Endpoint",
        url="/login",
        methods=["POST"],
        auth_params=AuthenticationMode.NONE,
        conc_params=ConcurrencyMode.AUTH_AND_PROC,
        processor=ProcessorType.STATIC_TEMPLATE,
        processor_action=ApiProcessorAction.JSON,
        content_type="text/html",
        request_args_mandatory=["username", "password"],
    ),
    BlueprintInfo(
        endpoint_id=40002,
        name="jslogin",
        description="js login endpoint",
        url="/js/login.js",
        methods=["GET"],
        auth_params=AuthenticationMode.NONE,
        conc_params=ConcurrencyMode.AUTH_AND_PROC,
        processor=ProcessorType.STATIC_TEMPLATE,
        processor_action=TemplateProcessorAction.STATIC_JS,
        override_target="js/login.js",
        content_type="text/javascript",
    ),
]


handler = BlueprintHandler(
    blueprints=Blueprint("routes_auth", __name__),
    infos=infos,
)


# pylint: disable=unused-argument


# pylint: disable=unused-argument
