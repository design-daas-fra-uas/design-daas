"""Object for a virtualized app using Guacamole."""

from dataclasses import dataclass
from typing import Optional
from app.daas.common.model import Environment
from app.daas.db.db_mappings import ORMMappingType, ORMModelDomain
from app.daas.objects.config_factory import get_empty_object_dict
from app.daas.objects.config_machine import MachineConfigBase
from app.daas.objects.object_api import ObjectApiMixin
from app.daas.objects.object_instance import InstanceObject
from app.qweb.logging.logging import LogTarget, Loggable
from app.qweb.processing.processor import QwebResult


@ORMModelDomain(ORMMappingType.Machine)
@dataclass(kw_only=True)
class MachineObject(ObjectApiMixin, MachineConfigBase):
    """Object for a virtualized app using Guacamole."""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        Loggable.__init__(self, LogTarget.OBJECT)

    def __repr__(self):
        return (
            f"{self.__class__.__qualname__}"
            f"(id={self.id},name={self.id_user},"
            f"obj_type={self.object_type},os_type={self.os_type})"
        )

    async def baseimage_finalize(self) -> QwebResult:
        ret = await self.vmsnapshot_create("root", "Initial snapshot")
        if ret is not None and ret.response_code == 200:
            self.object_state = "baseimage-final"
            if await self.update():
                return ret
            return QwebResult(400, {}, 1, "Error during db update")
        return ret

    async def environment_finalize(self, env: Environment, args: dict) -> QwebResult:
        if await self.env_finalize(env, args):
            return QwebResult(200, {})
        return QwebResult(400, {}, 1, "Env not finalized")

    async def environment_delete(self, env: Environment, args: dict) -> QwebResult:
        if await self.env_delete(env, args):
            return QwebResult(200, vars(env))
        return QwebResult(400, {}, 1, "Env not deleted")

    async def environment_get(self, name: str, args: dict) -> QwebResult:
        env = await self.env_get(name, args)
        if env is not None:
            return QwebResult(200, vars(env))
        return QwebResult(400, {}, 1, "No env")

    async def environments_get(self, args: dict) -> QwebResult:
        envs = await self.envs_get(args)
        return QwebResult(200, [vars(env) for env in envs])

    async def environment_start(
        self,
        env: Environment,
        userid: int,
        connect: bool,
        object_mode: str = "",
        args: Optional[dict] = None,
    ) -> Optional[InstanceObject]:
        """Starts environment instance"""
        args = args if args is not None else {}
        if not await self.verify_demand(userid):
            return None
        inst = await self.env_start(env, userid, connect, object_mode, args)
        if inst is not None:
            return await self._return_connected_instance(connect)
        return None

    async def environment_run(
        self,
        env: Environment,
        userid: int,
        connect: bool,
        object_mode: str = "",
        args: Optional[dict] = None,
    ) -> Optional[InstanceObject]:
        """Runs environment instance"""
        args = args if args is not None else {}

        if not await self.verify_demand(userid):
            return None
        inst = await self._get_db_instance(env)
        if inst is None:
            inst = await self.env_start(env, userid, connect, object_mode, args)
        if inst is not None:
            if object_mode != "":
                self.object_mode = "run-app"
                await self.update()
            await self.execute_task(inst, env.env_target, args)
            await self.set_extended_mode("done")
            return await self._return_connected_instance(connect)
        return None


async def get_empty_machine_object(userid: int, **kwargs) -> MachineObject:
    """Creates empty Container object"""
    dict_args = await get_empty_object_dict(
        object_type="vm",
        userid=userid,
        **kwargs,
    )
    return MachineObject(**dict_args)
