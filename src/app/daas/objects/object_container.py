"""Configuration for a containerized app using Guacamole."""

import asyncio
from dataclasses import dataclass
from typing import Optional
from app.daas.common.model import Environment
from app.daas.db.db_mappings import ORMMappingType, ORMModelDomain
from app.daas.objects.config_factory import get_empty_object_dict
from app.daas.objects.config_container import ContainerConfigBase
from app.daas.objects.object_api import ObjectApiMixin
from app.daas.objects.object_instance import InstanceObject
from app.qweb.logging.logging import LogTarget, Loggable
from app.qweb.processing.processor import QwebResult


@ORMModelDomain(ORMMappingType.Container)
@dataclass(kw_only=True)
class ContainerObject(ObjectApiMixin, ContainerConfigBase):
    """Configuration for a containerized app using Guacamole."""

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
        self.object_state = "baseimage-final"
        if await self.update():
            return QwebResult(200, {})
        return QwebResult(400, {}, 1, "Error during db update")

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
        args=None,
    ) -> Optional[InstanceObject]:
        """Starts environment instance"""
        if args is None:
            args = {}
        if not await self.verify_demand(userid):
            return None
        inst = await self.env_start(env, userid, connect, object_mode, args, True)
        if inst is not None:
            return await self._return_connected_instance(connect)
        return None

    async def environment_run(
        self,
        env: Environment,
        userid: int,
        connect: bool,
        object_mode: str = "",
        args=None,
    ) -> Optional[InstanceObject]:
        """Runs environment instance"""
        if args is None:
            args = {}
        if not await self.verify_demand(userid):
            return None
        inst = await self.env_start(env, userid, connect, object_mode, args, True)
        if inst is not None:
            if object_mode != "":
                self.object_mode = "run-app"
                await self.update()
                await asyncio.sleep(3)
            if await self.execute_task(inst, env.env_target, args):
                await self.set_extended_mode("done")
            return await self._return_connected_instance(connect)
        return None


async def get_empty_container_object(userid: int, **kwargs) -> ContainerObject:
    """Creates empty Container object"""
    dict_args = await get_empty_object_dict(
        object_type="container", userid=userid, **kwargs
    )
    return ContainerObject(**dict_args)
