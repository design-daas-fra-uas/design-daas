"""Handles blueprints"""

from dataclasses import dataclass, asdict
import traceback
from typing import Optional
from app.qweb.logging.logging import LogTarget, Loggable
from quart import Blueprint, Response, render_template, request, websocket
from app.qweb.auth.auth_qweb import QwebAuthenticatorBase
from app.qweb.blueprints.blueprint_info import BlueprintInfo
from app.qweb.common.config import (
    BlueprintHandlerConfig,
    QuartConfig,
    QuartProcessorConfig,
)
from app.qweb.processing.processor_files import FileProcessor
from app.qweb.processing.processor_templates import TemplateProcessor
from app.qweb.processing.processor_api import ApiProcessor
from app.qweb.processing.processor_websockets import WebsocketProcessor
from app.qweb.service.service_context import (
    CoreContext,
    BackendContext,
    ObjectContext,
)
from app.qweb.service.service_runtime import QwebProcessorContexts
from app.qweb.common.timings import Measurement
from app.qweb.processing.processor import (
    ProcessorRequest,
    ProcessorRequestContext,
    ProcessorType,
    QwebResult,
)
from app.qweb.service.service_tasks import QwebTaskManager


@dataclass
class QwebRequest:
    """A parsed request"""

    info: BlueprintInfo
    req: ProcessorRequest
    timing: Optional[Measurement]


# pylint: disable=too-many-instance-attributes
class BlueprintHandlerBase(Loggable):
    """Handler base class"""

    def __init__(
        self,
        blueprints: Blueprint,
        infos: list[BlueprintInfo],
    ):
        Loggable.__init__(self, LogTarget.SYS)
        self.fileproc = FileProcessor()
        self.tmplproc = TemplateProcessor()
        self.apiproc = ApiProcessor()
        self.socketproc = WebsocketProcessor()
        self.blueprints = blueprints
        self.infos = {}
        self.requestlog = []
        self.cfg_handler = BlueprintHandlerConfig(True, True, True, True, True, 3000)
        self.cfg_quart = QuartConfig("", "", "", "", "")
        for info in infos:
            self.infos[info.name] = info
            self._add_route(info)

    def _add_route(self, info: BlueprintInfo):
        """Registers info.url on the blueprint; every request goes to
        handle_request(info.name)"""

        # URL variables (<id>) are read from request.view_args later on
        async def view(**_url_args):
            return await self.handle_request(info.name)

        view.__name__ = info.name
        view.__doc__ = info.description
        if info.processor == ProcessorType.WEBSOCKET:
            self.blueprints.add_websocket(info.url, info.name, view)
        else:
            self.blueprints.add_url_rule(
                info.url, info.name, view, methods=info.methods
            )

    async def handle_request(self, name: str):
        """Handles a request of the route called name"""
        raise NotImplementedError("Implemented by BlueprintHandler")

    def set_configs(
        self,
        cfg_proc: QuartProcessorConfig,
        cfg_quart: QuartConfig,
        cfg_handler: BlueprintHandlerConfig,
    ):
        """Sets blueprint config"""
        self.cfg_proc = cfg_proc
        self.cfg_quart = cfg_quart
        self.cfg_handler = cfg_handler
        self.fileproc.set_configs(self.cfg_quart, self.cfg_proc)
        self.tmplproc.set_configs(self.cfg_quart, self.cfg_proc)
        self.apiproc.set_configs(self.cfg_quart, self.cfg_proc)
        self.socketproc.set_configs(self.cfg_quart, self.cfg_proc)

    def _log_request(
        self,
        info: BlueprintInfo,
        req: ProcessorRequest,
        timing: Optional[Measurement],
    ):
        entry = QwebRequest(info=info, req=req, timing=timing)
        self.requestlog.append(entry)

    async def _prepare_stage(
        self, name: str
    ) -> tuple[Optional[BlueprintInfo], Optional[ProcessorRequest]]:
        """Prepares Stage"""

        # Get Endpoint info
        info = self._get_info(name)
        if info is None:
            self._log_error(f"Info not available for {name}", 1)
            return None, None

        # Create Processor request
        req = await self._create_processor_request(info)
        if req is None:
            self._log_error(f"Context not available for {info.name}", 1)
        return info, req

    async def _extract_bearer(self) -> str:
        """Extracts bearer token"""

        bearer = ""
        # Extract header param
        hdrdict = request.headers
        if "Authorization" in hdrdict:
            if str(request.headers["Authorization"]).startswith("Bearer"):
                bearer = request.headers["Authorization"].split()[1]

        # Extract form param
        if "bearer" in await request.form:
            if str((await request.form)["bearer"]) != "":
                bearer = (await request.form)["bearer"]
        json_req = await request.get_json()
        if json_req is not None and "bearer" in json_req:
            if str(json_req["bearer"]) != "":
                bearer = json_req["bearer"]

        if bearer != "":
            bearer = str(bearer)
        return bearer

    async def _get_authmanager(self) -> QwebAuthenticatorBase:
        from app.qweb.service.service_runtime import get_qweb_runtime

        runtime = get_qweb_runtime()
        return runtime.services.authenticator

    async def _get_taskmanager(self) -> QwebTaskManager:
        from app.qweb.service.service_runtime import get_qweb_runtime

        runtime = get_qweb_runtime()
        return runtime.services.manager

    async def _get_contexts(
        self, info: BlueprintInfo, req: ProcessorRequest
    ) -> QwebProcessorContexts:
        from app.qweb.service.service_runtime import (
            get_qweb_runtime,
            QwebServiceRuntime,
        )

        result = QwebProcessorContexts(
            CoreContext({}, False),
            BackendContext({}, False),
            ObjectContext({}, {}, False),
        )
        runtime = get_qweb_runtime()
        if isinstance(runtime, QwebServiceRuntime):
            result = await runtime.get_contexts(info, req.request_context.request_args)
        return result

    async def _create_processor_request(
        self, info: BlueprintInfo
    ) -> Optional[ProcessorRequest]:
        token = ""
        bearer = ""
        url = ""
        if info.processor == ProcessorType.WEBSOCKET:
            token = ""
            url = websocket.url
        else:
            bearer = await self._extract_bearer()
            url = request.url
        target = self._get_processor_target(info)
        ctx = await self._get_request_context(info)
        if ctx is None:
            return None
        return ProcessorRequest(
            url=url,
            path=target,
            bearer=bearer,
            token=token,
            proctype=info.processor,
            apitask=info.processor_task,
            action=info.processor_action,
            content_type=info.content_type,
            static_args=info.static_args,
            request_context=ctx,
        )

    async def _get_request_context(
        self, info: BlueprintInfo
    ) -> Optional[ProcessorRequestContext]:
        mandatory = info.request_args_mandatory
        optional = info.request_args_optional
        common = info.request_args_common
        query = info.request_args_query
        file = info.request_args_file

        if info.processor == ProcessorType.WEBSOCKET:
            args_query = await self._read_socketargs(query)
            args = {**args_query}
            return ProcessorRequestContext(
                request_quart=None,
                request_websocket=websocket,
                request_args=args,
            )
        else:
            args_mandatory = await self._read_formargs(mandatory)
            if len(args_mandatory) != len(info.request_args_mandatory):
                self._log_error(
                    (
                        f"Argument size differs for mandatory args: "
                        f"{len(args_mandatory)} !="
                        f"{len(info.request_args_mandatory)}"
                    )
                )
                return None
            args_optional = await self._read_formargs(optional)
            args_common = await self._read_formargs(common)
            args_query = await self._read_queryargs(query)
            args_file = await self._read_fileargs(file)
            args = {
                **args_mandatory,
                **args_optional,
                **args_common,
                **args_query,
                **args_file,
            }
            return ProcessorRequestContext(
                request_quart=request, request_websocket=None, request_args=args
            )

    def _get_processor_target(self, info: BlueprintInfo) -> str:
        """Retrieves processor target for given BlueprintInfo"""
        result = ""
        if info.processor != ProcessorType.WEBSOCKET:
            if info.override_target == "":
                target = request.path
            else:
                target = info.override_target
            result = self._normalize_filename(target)
        return result

    async def _read_queryargs(self, needed: list[str]) -> dict:
        """Read form args from quart request"""
        result = {}
        queried = request.view_args
        if queried:
            for key in needed:
                if key in queried:
                    result[key] = queried[key]

        return result

    async def _read_socketargs(self, needed: list[str]) -> dict:
        """Read form args from quart websocket object"""
        result = {}
        queried = websocket.view_args
        if queried:
            for key in needed:
                if key in queried:
                    result[key] = queried[key]

        return result

    async def _read_fileargs(self, needed: list[str]) -> dict:
        """Read file args from quart request"""
        result = {}
        queried = await request.files
        if queried:
            for key in needed:
                if key in queried:
                    result[key] = queried[key]
        return result

    async def _read_formargs(self, needed: list[str]) -> dict:
        """Read form args from quart request"""
        result = {}
        form_data = await request.form
        json_data = await request.get_json()
        if form_data:
            for key in needed:
                retlist = form_data.getlist(key)
                if len(retlist) > 0:
                    result[key] = retlist[0]
        if len(result) != len(needed):
            if json_data:
                for key in needed:
                    if key in json_data:
                        result[key] = json_data[key]

        return result

    async def _create_error_response(
        self,
        msg: str,
        status_http: int = 500,
        status_sys: int = 1,
        content_type: str = "text/html",
        exception: Optional[Exception] = None,
    ) -> tuple[Response | dict, int]:
        """Creates error message response"""
        args = {
            "msg": msg,
            "status_http": status_http,
            "status_sys": status_sys,
            "exception": exception,
        }
        if content_type == "application/json":
            return self._create_error_response_dict(**args)
        return await self._create_error_response_text(**args)

    async def _create_error_response_text(
        self,
        msg: str,
        status_http: int = 500,
        status_sys: int = 1,
        exception: Optional[Exception] = None,
    ) -> tuple[Response, int]:
        """Creates error message response"""

        args, _ = self._create_error_response_dict(
            msg, status_http, status_sys, {}, exception
        )
        return (
            await render_template("layout-error.html", **args),
            status_http,
        )

    def _create_error_response_dict(
        self,
        msg: str,
        status_http: int = 500,
        status_sys: int = 1,
        data: Optional[dict] = None,
        exception: Optional[Exception] = None,
    ) -> tuple[dict, int]:
        """Create error dict"""
        data = data if data is not None else {}
        conf = self.cfg_handler
        error_msg = ""
        if exception is not None:
            if conf.enable_debugging:
                error_msg = f"{type(exception).__qualname__}! {exception}"
        error_trace = ""
        if conf.enable_debugging and conf.enable_exceptions_echo:
            error_trace = traceback.format_exc()
        return (
            asdict(
                QwebResult(status_http, data, status_sys, msg, error_msg, error_trace)
            ),
            status_http,
        )

    def _normalize_filename(self, name: str) -> str:
        """Normalizes filepath"""
        if name.startswith("/"):
            return name[1:]
        return name

    def _get_info(self, name: str) -> Optional[BlueprintInfo]:
        """Retrieves endpoint info"""
        if name in self.infos:
            return self.infos[name]
        return None

    async def _init_timing(self) -> Optional[Measurement]:
        timing = None
        if self.cfg_handler.enable_timings:
            formdata = await request.form
            if formdata is not None:
                val = formdata.getlist("timestamp")
                if len(val) > 0:
                    cli_ms = int(val[0])
                    timing = Measurement()
                    timing.start(cli_ms)
            json = await request.get_json()
            if json is not None and "timestamp" in json:
                cli_ms = json["timestamp"]
                timing = Measurement()
                timing.start(cli_ms)
        return timing

    async def _append_timing(self, result, timing: Optional[Measurement]):
        if timing is not None:
            timing.stop()
            if isinstance(result, dict):
                result["timings"] = asdict(timing)

    async def _append_echo_args(
        self, result: Response | dict | str, req: ProcessorRequest
    ):
        if self.cfg_handler.enable_args_echo and isinstance(result, dict):
            ctx = req.request_context
            qres = ctx.request_quart
            if qres is not None:
                result["http_file"] = qres.url
                result["http_method"] = qres.method
                result["http_params_form"] = ctx.request_args
                result["http_params_query"] = qres.view_args
