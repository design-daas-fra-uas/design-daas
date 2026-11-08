"""
QwebResult wrappers shared by MachineObject and ContainerObject: each one
calls the object's own implementation (configure_*, copy_installers, ...)
and turns its result into an API answer.
"""

from typing import Optional
from app.daas.common.model import Environment, File
from app.daas.objects.base_object import LIMIT_REACHED
from app.qweb.common.qweb_tools import get_database
from app.qweb.processing.processor import QwebResult


class ObjectApiMixin:
    """API answers of a DaaS object (see module docstring)"""

    # pylint: disable=no-member

    async def baseimage_create(self, args: dict) -> QwebResult:
        """Creates the base image when the owner's limits allow it"""
        if not await self.verify_demand(args["id_owner"]):
            return QwebResult(400, {}, 1, LIMIT_REACHED)
        code, str_out, str_err = await self.create(args)
        status = 200 if code == 0 else 400
        return QwebResult(status, {}, code, f"{str_out}{str_err}")

    async def baseimage_clone(self, oldid: str, args: dict) -> QwebResult:
        """Clones oldid into this object when the owner's limits allow it"""
        if not await self.verify_demand(args["id_owner"]):
            return QwebResult(400, {}, 1, LIMIT_REACHED)
        code, str_out, str_err = await self.clone(oldid, args)
        status = 200 if code == 0 else 400
        return QwebResult(status, {}, code, f"{str_out}{str_err}")

    async def environment_create(self, args: dict) -> QwebResult:
        """Creates an environment of this object"""
        env = await self.env_create([], [], args)
        if env is not None:
            return QwebResult(200, vars(env))
        return QwebResult(400, {}, 1, "Env not created")

    async def environment_stop(
        self, env: Environment, force: bool, args: dict
    ) -> QwebResult:
        """Stops the instance of an environment"""
        if await self.env_stop(env, force, args):
            return QwebResult(200, {}, response_url="-")
        return QwebResult(400, {}, 1, "Env not stopped")

    async def cfg_applist(
        self, obj: str, env: Optional[Environment], args: dict
    ) -> QwebResult:
        """Sets the app list (JSON) of the object or environment"""
        if await self.configure_applist(obj, env, args):
            return QwebResult(200, {})
        return QwebResult(400, {}, 1, "Error on applist config")

    async def cfg_tasklist(
        self, obj: str, env: Optional[Environment], args: dict
    ) -> QwebResult:
        """Sets the task list (JSON) of the object or environment"""
        if await self.configure_tasklist(obj, env, args):
            return QwebResult(200, {})
        return QwebResult(400, {}, 1, "Error on tasklist config")

    async def cfg_set_target(
        self, obj: str, env: Optional[Environment], args: dict
    ) -> QwebResult:
        """Sets the start target (JSON) of the object or environment"""
        if await self.configure_target(obj, env, args):
            return QwebResult(200, {})
        return QwebResult(400, {}, 1, "Error on target config")

    async def cfg_installers_deploy(
        self,
        files: list[File],
        installers: list[str],
        userid: int,
        env: Optional[Environment],
        args: dict,
    ) -> QwebResult:
        """Copies the installer files into the instance"""
        if await self.copy_installers(files, installers, userid, env, args):
            return QwebResult(200, {})
        return QwebResult(400, {}, 1, "error on installer_deploy")

    async def cfg_installers_execute(
        self, installers: list[str], env: Optional[Environment], args: dict
    ) -> QwebResult:
        """Runs the installer tasks in the instance"""
        if await self.execute_tasks(installers, env, args):
            return QwebResult(200, {})
        return QwebResult(400, {}, 1, "error on installer_execute")

    async def cfg_install(
        self,
        files: list[File],
        installers: list[str],
        userid: int,
        env: Optional[Environment],
        args: dict,
    ) -> QwebResult:
        """Copies the installers, then runs them"""
        if await self.copy_installers(files, installers, userid, env, args):
            if await self.execute_tasks(installers, env, args):
                return QwebResult(200, {})
        return QwebResult(400, {}, 1, "error on installation")

    async def update(self) -> bool:
        """Writes the object to the database"""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        return await dbase.update_daas_object(self)
