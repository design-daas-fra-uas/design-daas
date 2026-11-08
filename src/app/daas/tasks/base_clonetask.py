"""
Shared flow of CreateTask and CloneTask: boot and finalize the base image,
then create, configure, install, finalize and start the environment.
"""

import asyncio
import time
from dataclasses import asdict
from typing import Awaitable, Callable, Optional
from quart import json
from app.daas.common.model import Environment, File
from app.daas.objects.object_application import ApplicationObject
from app.daas.objects.object_container import ContainerObject
from app.daas.objects.object_instance import InstanceObject
from app.daas.objects.object_machine import MachineObject
from app.daas.tasks.task_config import (
    ApplistObject,
    CloneTaskConfig,
    TargetObject,
    TasklistObject,
)
from app.plugins.platform.phases.enums import PhasesSystemTask
from app.qweb.common.qweb_tools import get_database, run_system_task
from app.qweb.logging.logging import LogTarget, Loggable
from app.qweb.processing.processor import QwebResult


class CloneTaskBase(Loggable):
    """Base of CreateTask and CloneTask (see module docstring)"""

    # Name of the flow in logs and error messages
    kind = "Create"

    def __init__(self, cfg: CloneTaskConfig):
        Loggable.__init__(self, LogTarget.AUTOMATION)
        self.cfg = cfg
        assert self.cfg is not None
        assert self.cfg.args is not None
        assert self.cfg.args.args is not None
        assert self.cfg.args.args["app"] is not None
        assert self.cfg.args.args["obj"] is not None
        assert self.cfg.args.args["inst"] is not None
        self.args = self.cfg.args.args
        assert self.args is not None
        assert isinstance(self.args["app"], ApplicationObject)
        assert isinstance(self.args["obj"], MachineObject | ContainerObject)
        assert isinstance(self.args["inst"], InstanceObject)
        self.app: ApplicationObject = self.args["app"]
        self.obj: MachineObject | ContainerObject = self.args["obj"]
        self.inst: InstanceObject = self.args["inst"]
        self.env: Optional[Environment] = None

    async def _run_steps(
        self, kind: str, steps: list[tuple[str, Callable[[], Awaitable]]]
    ) -> bool:
        """
        Runs the steps of a clone/create flow in order and logs each one with
        its duration. Stops at the first step that returns a falsy value and
        logs which one it was (shown to the user as the object's mode too).
        """
        flow = f"{kind} {self.app.name} -> {self.obj.id}"
        started = time.monotonic()
        self._log_info(f"{flow}: started")
        for number, (name, step) in enumerate(steps, start=1):
            step_started = time.monotonic()
            self._log_info(f"{flow}: step {number}/{len(steps)} {name}")
            if not await step():
                if not await self._object_exists():
                    self._log_info(f"{flow}: stopped, the object was deleted")
                    return False
                msg = f"{flow}: FAILED at step {number}/{len(steps)} {name}"
                self._log_error(f"{msg} after {_duration(step_started)}", 1)
                await self.obj.set_extended_mode(f"Failed: {name}")
                return False
            self._log_info(
                f"{flow}: step {number}/{len(steps)} {name} done "
                f"({_duration(step_started)})"
            )
        self._log_info(f"{flow}: finished in {_duration(started)}")
        return True

    async def run(self) -> QwebResult:
        args = self.args
        ok = await self._run_steps(
            self.kind,
            [
                ("boot and finalize base image", self._handle_state_baseimage),
                ("create environment", lambda: self._create_env(args)),
                ("configure connection", self._configure_connection),
                ("configure environment", lambda: self._configure_env(args)),
                ("install app", lambda: self._install_env(args)),
                ("finalize environment", lambda: self._finalize_env(args)),
                ("start app", lambda: self._run_env(args)),
            ],
        )
        if ok:
            return QwebResult(200, {})
        return QwebResult(
            400, {}, 1, f"{self.kind} failed: {self.obj.object_mode_extended}"
        )

    async def _handle_state_baseimage(self) -> bool:
        await self._update_state("Wait for instance boot (baseimage)")
        await self._wait_for_baseimage_boot()
        await self._update_state("Finalize baseimage")
        finalized = await self.obj.baseimage_finalize()
        if finalized is None or finalized.response_code != 200:
            await self._update_state("Error on Finalize")
            return False
        await self._update_state("Finalized baseimage")
        return True

    async def _wait_for_baseimage_boot(self):
        """Waits until the base image's instance is online"""
        await self._wait_for_inst_baseimage()

    async def _create_env(self, args: dict) -> bool:
        await self._wait_for_inst_env()
        await self._update_state(f"Create environment: {args['env']}")
        envargs = await self._create_envargs(args)
        self.env = await self.obj.env_create([], [], envargs)
        if self.env is None:
            await self._update_error(f"Environment not created: {args['env']}")
            return False
        await asyncio.sleep(3)
        await self._wait_for_inst_env()
        await self._update_state(f"Created environment: {args['env']}")
        return True

    async def _configure_connection(self) -> bool:
        await self._update_state("Configure connections")
        await self._run_task_configure_connection()
        await self._upgrade_to_env_connection()
        await self._update_state("Configured connection")
        await asyncio.sleep(2)
        return True

    async def _configure_env(self, args: dict) -> bool:
        await self._update_state(f"Configure environment: {args['env']}")
        tasklist = await self._get_object_tasklist()
        applist = await self._get_object_applist()
        target = await self._get_object_target()
        await self.obj.cfg_tasklist(tasklist, self.env, args)
        await self.obj.cfg_applist(applist, self.env, args)
        await self.obj.cfg_set_target(target, self.env, args)
        return await self.obj.update()

    async def _install_env(self, args: dict) -> bool:
        await self._update_state(f"Install environment: {args['env']}")
        files = await self._get_files(self.app)
        installers = await self._get_installers(self.app)
        installed = await self.obj.cfg_install(
            files, installers, args["id_owner"], self.env, args
        )
        if installed is None or installed.response_code != 200:
            await self._update_error(
                f"Error in Configure environment: {args['env']}", 1
            )
            return False
        return True

    async def _finalize_env(self, args: dict) -> bool:
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        assert self.env is not None
        await self._update_state(f"Finalize environment: {args['env']}")
        await self.obj.env_finalize(self.env, args)
        await dbase.update_environment(self.env)
        await self._run_task_configure_connection()
        return True

    async def _run_env(self, args: dict) -> Optional[InstanceObject]:
        assert self.env is not None
        await self._update_state(f"Run environment: {args['env']}")
        return await self.obj.environment_run(
            self.env, args["id_owner"], True, "run-app", args
        )

    async def _upgrade_to_env_connection(self) -> bool:
        from app.daas.db.database import Database

        await self._update_state("Upgrade to env connection")
        dbase = await get_database(Database)
        assert self.env is not None
        obj = await dbase.get_daas_object(self.obj.id)
        inst = await dbase.get_instance_by_id(self.inst.id)
        assert inst is not None
        inst.id_env = self.env.id
        inst.env = self.env
        updated = await dbase.update_instance(inst)
        assert updated
        assert isinstance(obj, MachineObject | ContainerObject)
        self.obj = obj
        self.inst = inst
        await self._update_state("Upgraded to env connection")
        return updated

    async def _object_exists(self) -> bool:
        """False when the user deleted the object while the flow was running:
        then nothing may be written for it (an update would insert it again)"""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        return await dbase.get_daas_object(self.obj.id) is not None

    async def _get_files(
        self,
        app: ApplicationObject,
    ) -> list[File]:
        file = await app.get_file()
        files = []
        if file is not None:
            files.append(file)
        return files

    async def _get_installers(
        self,
        app: ApplicationObject,
    ) -> list[str]:
        installer = await app.get_installer()
        installers = []
        if installer != "":
            installers.append(installer)
        return installers

    async def _get_object_tasklist(self) -> str:
        ttype = self.app.installer_type
        cmd = self.app.installer
        args = self.app.installer_args
        obj = TasklistObject(ttype, cmd, args)
        return json.dumps([asdict(obj)])

    async def _get_object_applist(self) -> str:
        obj = ApplistObject("exec_app", self.app.target, self.app.target_args)
        return json.dumps([asdict(obj)])

    async def _get_object_target(self) -> str:
        obj = TargetObject(self.app.name, self.app.target, self.app.target_args)
        return json.dumps(asdict(obj))

    async def _create_envargs(self, args: dict) -> dict:
        envargs = args.copy()
        envargs["name"] = args["env"].lower()
        return envargs

    async def _update_state(self, msg: str, code: int = -1):
        self._log_info(msg, code)
        await self.obj.set_extended_mode(msg)

    async def _update_error(self, msg: str, code: int = -1):
        self._log_error(msg, code)
        await self.obj.set_extended_mode(msg)

    async def _wait_for_inst_baseimage(self):
        self._log_info("Waiting for instance to boot (baseimage)")
        await self._run_task_wait_for_inst()
        await self.obj.set_extended_mode("Object booted")

    async def _wait_for_inst_env(self):
        await self._run_task_wait_for_inst()
        await self.obj.set_extended_mode("Object started")
        self._log_info("Creating env")

    async def _run_task_wait_for_inst(self):
        ttype = PhasesSystemTask.PHASES_WAIT_FOR_INSTANCE.value
        task = await run_system_task(
            ttype, self.obj.id_owner, self.obj.id, self.inst.id
        )
        assert task is not None
        self._log_info("Waiting")
        await task.task
        self._log_info("Waited")

    async def _run_task_configure_connection(self):
        ttype = PhasesSystemTask.PHASES_CONFIGURE_CONNECTION.value
        task = await run_system_task(
            ttype, self.obj.id_owner, self.obj.id, self.inst.id
        )
        assert task is not None
        await task.task


def _duration(started: float) -> str:
    """Time since started (time.monotonic()), e.g. "12 min 3 s" or "8 s" """
    seconds = int(time.monotonic() - started)
    if seconds < 60:
        return f"{seconds} s"
    return f"{seconds // 60} min {seconds % 60} s"
