"""Service runtime"""

import sys
import asyncio
from dataclasses import asdict
from typing import Any, Optional
import nest_asyncio
from quart import Quart
from quart_cors import cors
from app.qweb.logging.logging import Loggable, QwebLogManager, LogTarget, LoggerConfig
from app.qweb.auth.auth_dummy import QwebDummyAuthenticator
from app.qweb.blueprints.blueprint_info import BlueprintInfo
from app.qweb.common.config import ConfigReader, QwebConfig
from app.qweb.service.service_context import (
    BackendContext,
    ObjectContext,
    QwebBackend,
    QwebObjectLayer,
    QwebProcessorContexts,
    ServiceComponent,
    CoreContext,
)
from app.qweb.service.service_providers import (
    BackendContextProvider,
    CoreContextProvider,
    ObjectLayerContextProvider,
)
from app.qweb.service.service_tasks import QwebTaskManager
from app.qweb.common.tomlfile import read_toml_with_local

RUNTIME_VERSION = "1.0.0"


# pylint: disable=import-outside-toplevel
class QwebServiceRuntime(Loggable):
    """Service runtime for qweb"""

    def __init__(self, qwebfile: str = "", authfile: str = ""):
        self.reader = ConfigReader(qwebfile=qwebfile, authfile=authfile)
        self.cfg_qweb = self.reader.cfg_qweb
        self.cfg_auth = self.reader.cfg_auth
        self.app = self.__create_app()
        self.services = CoreContextProvider(
            QwebTaskManager(), QwebDummyAuthenticator(self.cfg_auth)
        )
        self.blueprints = {}
        self.backends = BackendContextProvider()
        self.layers = ObjectLayerContextProvider()
        self.service_task = None

        data = self.get_config("logging.toml")
        self.cfg_log = LoggerConfig(**data["log"])
        if not self.cfg_log.log_dir.startswith("/"):
            self.cfg_log.log_dir = (
                f"{self.cfg_qweb.sys.root_path}"
                f"/{self.cfg_qweb.sys.data_path}"
                f"/{self.cfg_log.log_dir}"
            )

        logman = QwebLogManager(self.cfg_log)
        logman.initialize_logging()
        Loggable.__init__(self, LogTarget.RUNTIME)
        self._log_info("Initialized runtime")

    def __repr__(self) -> str:
        if self.cfg_qweb.handler.enable_debugging:
            ext = self.status_extended()
            short = self.status_short()
            return f"{ext}\n{short}"
        return self.status_short()

    def status_short(self) -> str:
        return (
            f"--- QwebServiceRuntime State Begin ---\n"
            f"Backends     : {len(self.backends.backends)}\n"
            f"Layers       : {len(self.layers.layers)}\n"
            f"Qweb Services: {2}\n"
            f"Blueprints   : {len(self.blueprints)}\n"
            f"EndpointTasks: {len(self.services.manager.tasks_endpoint)}\n"
            f"SystemTasks  : {len(self.services.manager.tasks_system)}\n"
            f"Version      : {RUNTIME_VERSION}\n"
            f"--- QwebServiceRuntime State End ---"
        )

    def status_extended(self) -> str:
        bstates = []
        for name, backend in self.backends.backends.items():
            bstates.append(f"  {name}={backend}")
        backends = "\n".join(bstates)
        lstates = []
        for name, layer in self.layers.layers.items():
            lstates.append(f"  {name}={layer}")
        layers = "\n".join(lstates)
        sstates = [
            f"  authman={self.services.authenticator}",
            f"  taskman={self.services.manager}",
        ]
        services = "\n".join(sstates)
        bpstates = []
        for name, bp in self.blueprints.items():
            bpstates.append(f"  {bp.endpoint_id}={bp}")
        blueprints = "\n".join(bpstates)
        epstates = []
        for name, ep in self.services.manager.tasks_endpoint.items():
            epstates.append(f"  {name}={ep.__module__}.{ep.__qualname__}")
        tasks = "\n".join(epstates)
        spstates = []
        for name, sp in self.services.manager.tasks_system.items():
            spstates.append(f"  {name}={sp.__module__}.{sp.__qualname__}")
        systasks = "\n".join(spstates)
        return (
            f"--- QwebServiceRuntime State Begin ---\n"
            f"Backends:\n{backends}\n"
            f"Layers:\n{layers}\n"
            f"Qweb Services:\n{services}\n"
            f"Blueprints:\n{blueprints}\n"
            f"EndpointTasks:\n{tasks}\n"
            f"SystemTasks:\n{systasks}\n"
            f"--- QwebServiceRuntime State End ---"
        )

    def get_config_qweb(self) -> QwebConfig:
        """Returns qweb config"""
        return self.cfg_qweb

    def get_config(self, filename: str) -> dict:
        """Reads config from config folder"""
        return self._read_toml_file(filename)

    def add_apitasks(self, tasks: list[tuple[str, Any]]):
        """Adds a new api task to the taskmanager"""
        for task in tasks:
            name, func = task
            self.services.manager.add_task_endpoint(name, func)

    def add_systasks(self, tasks: list[tuple[str, Any]]):
        """Adds a new sys task to the taskmanager"""
        for task in tasks:
            name, func = task
            self.services.manager.add_task_system(name, func)

    def add_handlers(self, handlers: list[Any]) -> bool:
        """Adds BlueprintHandler"""
        from app.qweb.blueprints.blueprint_handler import BlueprintHandler

        result = False
        for handler in handlers:
            if isinstance(handler, BlueprintHandler):
                handler.set_configs(
                    self.cfg_qweb.proc, self.cfg_qweb.quart, self.cfg_qweb.handler
                )
                self.app.register_blueprint(handler.blueprints)
                for name, data in handler.infos.items():
                    self.blueprints[name] = data
                result = True
            else:
                result = False
                break
        return result

    def add_object_layers(self, layers: list[QwebObjectLayer]) -> bool:
        """Adds new object layers"""
        result = True
        for layer in layers:
            ret = self.layers.add(layer.name, layer)
            if not ret:
                result = False
                break
        return result

    def add_backend(self, backend: QwebBackend) -> bool:
        """Adds new backend"""
        result = True
        ret = self.backends.add(backend.name, backend)
        if not ret:
            result = False
        else:
            backend.registered = True
        return result

    async def start(self) -> bool:
        """Runs service"""
        print(self.__repr__())
        ret = await self.__start_app()
        return ret

    async def stop(self) -> bool:
        """Stops service"""
        await self.stop_backends()
        await self.stop_tasks()
        return True

    async def stop_backends(self) -> bool:
        """Stops backends"""
        return await self.__stop_app()

    async def stop_tasks(self) -> bool:
        """Stops tasks"""
        tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
        for task in tasks:
            self._log_info(f"Shutting down task: {task.get_name()}")
            task.cancel()
        if len(tasks) > 0:
            await asyncio.gather(*tasks, return_exceptions=True)
        return True

    async def get_contexts(
        self, info: BlueprintInfo, args: dict
    ) -> QwebProcessorContexts:
        """Get all contexts"""
        ctx_service = self.__get_service_context()
        ctx_backends = self.__get_backend_context(info)
        ctx_objects = await self.__get_object_context(info, args)
        return QwebProcessorContexts(ctx_service, ctx_backends, ctx_objects)

    def _read_toml_file(self, file: str) -> dict[str, Any]:
        """Reads toml file from config folder"""
        qweb_conf = self.get_config_qweb()
        config_path = qweb_conf.quart.config_folder
        return read_toml_with_local(f"{config_path}/{file}")

    def __get_service_context(self) -> CoreContext:
        needed = []
        needed.append(ServiceComponent.AUTH)
        needed.append(ServiceComponent.TASK)
        return self.services.create_context(needed)

    def __get_backend_context(self, info: BlueprintInfo) -> BackendContext:
        return self.backends.create_context(info.backends)

    async def __get_object_context(
        self, info: BlueprintInfo, args: dict
    ) -> ObjectContext:
        return await self.layers.create_context(needed=info.objects, args=args)

    def __create_app(self):
        from app.qweb.blueprints.blueprint_defaults import (
            handler as handler_default,
        )

        sys.setrecursionlimit(self.cfg_qweb.handler.recursion_limit)
        quartargs = asdict(self.cfg_qweb.quart)
        quartargs.pop("webroot_folder")
        quartargs.pop("config_folder")
        self.app = Quart(__name__, **quartargs)

        # Cors
        if self.cfg_qweb.cors.enabled:
            corsargs = asdict(self.cfg_qweb.cors)
            corsargs.pop("enabled")
            self.app = cors(self.app, **corsargs)

        # Blueprint config
        handler_default.set_configs(
            self.cfg_qweb.proc, self.cfg_qweb.quart, self.cfg_qweb.handler
        )

        # Blueprints
        self.app.register_blueprint(handler_default.blueprints)

        return self.app

    async def __stop_app(self) -> bool:
        # Reverse start order: the container backend started the service
        # containers (MariaDB, RabbitMQ) first, so it must stop them last,
        # after the database and messaging backends have disconnected
        for name, backend in reversed(list(self.backends.backends.items())):
            if isinstance(backend, QwebBackend):
                self._log_info(f"Stopping backend {name}")
                try:
                    await backend.disconnect()
                except Exception as exe:
                    t = type(exe)
                    self._log_info(
                        f"Error stopping backend {name}: {t.__module__}.{t.__qualname__}: {exe}"
                    )

        self._log_info("Stopping Service")
        if self.service_task is not None:
            self.service_task.cancel()
            asyncio.gather(self.service_task, return_exceptions=True)
            return True
        return False

    async def __start_app(self) -> bool:
        runargs = asdict(self.cfg_qweb.run)
        if self.cfg_qweb.ssl.enabled:
            runargs.update(asdict(self.cfg_qweb.ssl))
        if "enabled" in runargs:
            runargs.pop("enabled")
        if self.app is not None:
            nest_asyncio.apply()
            self.service_task = asyncio.create_task(self.app.run_task(**runargs))
            await self.service_task
            return True
        return False


SINGLETON: Optional[QwebServiceRuntime] = None


def get_qweb_runtime(qwebfile: str = "", authfile: str = "") -> QwebServiceRuntime:
    """Obtains singleton instance"""
    global SINGLETON
    if SINGLETON is None:
        SINGLETON = QwebServiceRuntime(qwebfile=qwebfile, authfile=authfile)
    return SINGLETON
