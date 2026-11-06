"""Base app on top of DaasObject"""

from abc import abstractmethod
import secrets
from dataclasses import dataclass
from datetime import datetime
from typing import Optional
from app.daas.common.enums import BackendName
from app.daas.common.model import DaasObject, Environment, RessourceInfo
from app.daas.container.docker.DockerRequest import DockerRequest
from app.daas.objects.object_instance import InstanceObject
from app.daas.vm.proxmox.ProxmoxApi import ApiProxmox
from app.plugins.platform.phases.enums import PhasesSystemTask
from app.qweb.common.qweb_tools import (
    get_backend_component,
    get_database,
    get_service,
    run_system_task,
)
from app.qweb.processing.processor import QwebResult
from app.qweb.service.service_context import ServiceComponent
from app.qweb.service.service_tasks import QwebTaskManager, ScheduledTask

# Globals
EXCLUDED_PROPERTIES = [
    "id_proxmox",
    "stateinfo",
    "os_password",
    "os_username",
    "vnc_username",
    "vnc_password",
    "vnc_port_instance",
    "vnc_port_system",
]


# Answer when verify_demand refuses a new object or instance
LIMIT_REACHED = "Resource limit reached"


@dataclass
class DaasBaseObject(DaasObject):
    """Acts as a baseclass for the For MachineApp and ContainerApp"""

    async def baseimage_delete(self) -> QwebResult:
        """Delete the object"""
        inst = await self._get_db_instance()
        if inst is not None:
            await self.stop(inst, True)
        if await self.delete():
            return QwebResult(200, {})
        return QwebResult(400, {}, 1, "Object deletion failed")

    async def baseimage_start(
        self, userid: int, connect: bool = False, object_mode: str = ""
    ) -> Optional[InstanceObject]:
        """Starts the object"""
        return await self.start(userid, connect, object_mode)

    async def baseimage_stop(self, instance: InstanceObject, force: bool) -> QwebResult:
        """Stops the object"""
        success = await self.stop(instance, force)
        if success:
            return QwebResult(200, {})
        return QwebResult(400, {}, 1, "Object was not stopped")

    async def baseimage_status(self) -> QwebResult:
        return QwebResult(200, await self.status())

    async def verify_demand(self, userid: int) -> bool:
        """True when the user's limits allow starting this object"""
        from app.daas.resources.limits.ressource_limits import RessourceLimits

        # A running object is already part of the user's usage: restarting it
        # or switching it to an environment needs nothing on top
        if await self._get_db_instance() is not None:
            return True
        limits = await get_backend_component(BackendName.LIMITS, RessourceLimits)
        demand_vm = 0
        demand_cnt = 0
        if self.is_machine():
            demand_vm = 1
        else:
            demand_cnt = 1
        info = RessourceInfo(
            userid,
            demand_vm,
            demand_cnt,
            1,
            self.hw_cpus,
            self.hw_memory,
            self.hw_disksize,
        )
        if await limits.verify_demand(userid, info):
            return True
        self._log_info(f"Resource limit reached for user {userid}: {self.id}")
        return False

    async def status(self) -> dict:
        """Returns status information"""
        from app.daas.resources.info.sysinfo import Systeminfo

        result = self.get_data()
        infotool = await get_backend_component(BackendName.INFO, Systeminfo)
        for prop in infotool.config.excluded_object_properties:
            if prop in result:
                result.pop(prop)
        return result

    async def change_owner(self, owner: int) -> bool:
        """Adjusts object to new owner"""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        await self.start_prepare(True)
        self.id_owner = owner
        await dbase.update_daas_object(self)
        return True

    async def insert_pending_instance(
        self, userid: int, env: Optional[Environment] = None
    ) -> InstanceObject:
        """Insert new instance into databse"""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        if self.is_container():
            api = await get_backend_component(BackendName.CONTAINER, DockerRequest)
            container_name = await self.get_container_tag()
            if env is not None:
                container_name = await self.get_environment_tag(env.name)
            adr = await api.docker_get_container_ip(container_name)
        else:
            api = await get_backend_component(BackendName.VM, ApiProxmox)
            container_name = ""
            adr = f"{api.config_prox.prefixip}.{self.id_proxmox}"
        instance = self._create_new_instance(
            app=self,
            env=env,
            id_owner=userid,
            host=adr,
            container=container_name,
            created_at=datetime.now(),
        )
        await dbase.create_instance(instance)
        assert instance is not None, "Pending instance is none"
        return instance

    async def start_prepare(self, keep_connections: bool = False) -> bool:
        """Prepare instance start"""
        await self._kill_object_tasks()

        instance = await self._get_db_instance()
        if instance is not None and keep_connections is False:
            await self.stop(instance, True)
        return True

    async def start_finalize(
        self, userid: int, object_mode: str = ""
    ) -> bool:
        """Finalize instance start"""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        inst = await self.insert_pending_instance(userid)
        if inst is None:
            return False
        await self.run_system_task_postboot(inst)
        self.object_mode = object_mode
        self.object_mode_extended = "booting"
        return await dbase.update_daas_object(self)

    async def run_system_task_postboot(
        self, inst: InstanceObject
    ) -> Optional[ScheduledTask]:
        tasktype = PhasesSystemTask.PHASES_POSTBOOT_ACTIONS.value
        return await run_system_task(tasktype, inst.id_owner, self.id, inst.id)

    async def stop_prepare(self, instance: InstanceObject, force: bool) -> bool:
        """Prepare instance stop"""
        await instance.disconnect(force)
        return True

    async def stop_finalize(self, instance: InstanceObject) -> bool:
        """Finalize instance stop"""
        from app.daas.db.database import Database

        await self._kill_object_tasks()
        dbase = await get_database(Database)
        await dbase.delete_instance(instance)
        self.object_mode = "stopped"
        self.object_mode_extended = "stopped"
        await dbase.update_daas_object(self)
        self._log_info(f"Stopped instance {instance.id}")
        return True

    async def delete(self) -> bool:
        """delete the instance."""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        if self.is_machine():
            deleted = await self._delete_vm()
        else:
            deleted = await self._delete_image()
        if deleted is True:
            return await dbase.delete_daas_object(self)
        return False

    async def _delete_vm(self) -> bool:
        api = await get_backend_component(BackendName.VM, ApiProxmox)
        node = api.config_prox.node
        resp, data = await api.prox_vmdelete(node, self.id_proxmox)
        if resp is not None and resp.status == 200 and data.get("exitstatus") == "OK":
            return True
        # Already gone (removed in Proxmox, or a reset database): only the row is left
        resp_list, vms = await api.prox_vmlist(node)
        if resp_list is not None and resp_list.status == 200:
            if all(int(vm["vmid"]) != self.id_proxmox for vm in vms.get("data", [])):
                self._log_info(f"VM {self.id_proxmox} does not exist, removing {self.id}")
                return True
        self._log_error(f"Deleting VM {self.id_proxmox} failed: {data}")
        return False

    async def _delete_image(self) -> bool:
        api = await get_backend_component(BackendName.CONTAINER, DockerRequest)
        tag = await self.get_container_tag()
        # A container can run without an instance row (e.g. after a backend
        # restart), so baseimage_delete did not stop it; it is named after the
        # tag. Without this the forced image delete only removes the tag and
        # the container keeps running. Containers run with remove=True.
        await api.docker_container_stop(tag, True)
        code, _, msg = await api.docker_image_delete(tag)
        if code == 0:
            return True
        # Already gone: only the row is left
        if msg == "Image not found":
            self._log_info(f"Image {tag} does not exist, removing {self.id}")
            return True
        self._log_error(f"Deleting image {tag} failed: {msg}")
        return False

    async def set_contype(self, contype: str):
        """Sets extended object mode"""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        self._log_debug(f"CONTYPE: {contype}")
        self.viewer_contype = contype
        await dbase.update_daas_object(self)

    async def set_extended_mode(self, extmode: str):
        """Sets extended object mode"""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        self.object_mode_extended = extmode
        await dbase.update_daas_object(self)

    async def _get_db_instance(
        self, env: Optional[Environment] = None
    ) -> Optional[InstanceObject]:
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        if env is not None:
            return await dbase.get_instance_by_envid(env.id)
        return await dbase.get_instance_by_objid(self.id)

    async def _get_db_object(self, id: str) -> Optional[DaasObject]:
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        return await dbase.get_daas_object(id)

    async def get_container_tag(self):
        """Creates container tag from object"""
        id_lower = self.id.lower()
        return f"daas.{id_lower}"

    async def get_environment_tag(self, name: str):
        """Creates environment tag from object"""
        id_lower = self.id.lower()
        return f"daas.{id_lower}.{name}"

    def is_machine(self) -> bool:
        """Checks if current object is a virtual Machine"""
        if self.object_type == "vm":
            return True
        return False

    def is_container(self) -> bool:
        """Checks if current object is a container"""
        if self.object_type == "container":
            return True
        return False

    def is_windows(self) -> bool:
        """Checks if current object is a windows object"""
        if self.is_machine():
            if self.os_type in "win10, win11":
                return True
        return False

    def has_ceph_filesystems(self) -> bool:
        """Checks if ceph is enabled via config"""
        if self.ceph_public or self.ceph_shared or self.ceph_user:
            return True
        return False

    async def _return_connected_instance(
        self, connect: bool
    ) -> Optional[InstanceObject]:
        inst = await self._get_db_instance()
        if connect:
            if inst is not None and inst.id_con is None:
                con = await inst.connect(self.viewer_contype)
                if con is not None:
                    return inst
        return inst

    async def _check_resource_limit(self) -> bool:
        return True

    def inherit_object_properties(self, obj: DaasObject):
        """Inherits property values from given object"""
        self.id = obj.id
        self.id_user = obj.id_user
        self.id_owner = obj.id_owner
        self.id_proxmox = obj.id_proxmox
        self.id_docker = obj.id_docker
        self.object_state = obj.object_state
        self.object_type = obj.object_type
        self.object_tasks = obj.object_tasks
        self.object_apps = obj.object_apps
        self.object_target = obj.object_target
        self.object_storage = obj.object_storage
        self.os_wine = obj.os_wine
        self.os_type = obj.os_type
        self.os_username = obj.os_username
        self.os_password = obj.os_password
        self.os_installer = obj.os_installer
        self.vnc_username = obj.vnc_username
        self.vnc_password = obj.vnc_password
        self.vnc_port_system = obj.vnc_port_system
        self.vnc_port_instance = obj.vnc_port_instance
        self.extra_args = obj.extra_args

    def _create_new_instance(
        self,
        app: DaasObject,
        env: Optional[Environment],
        id_owner: int,
        host: str,
        container: str,
        created_at: datetime,
    ) -> InstanceObject:
        randid = secrets.token_urlsafe(16)
        envid = None
        if env is not None:
            envid = env.id
        return InstanceObject(
            id=randid,
            id_app=app.id,
            id_env=envid,
            id_owner=id_owner,
            app=app,
            env=env,
            host=host,
            id_con=None,
            container=container,
            created_at=created_at,
            connected_at=created_at,
            booted_at=created_at,
        )

    def _create_new_environment(
        self,
        obj: DaasObject,
        name: str,
        id_backend: str,
        created_at: datetime,
    ) -> Environment:
        randid = secrets.token_urlsafe(16)
        if id_backend == "":
            id_backend = secrets.token_urlsafe(16)
        return Environment(
            id=randid,
            id_backend=id_backend,
            id_object=obj.id,
            name=name,
            state="environment-create",
            env_tasks=[],
            env_apps=[],
            env_target={},
            created_at=created_at,
        )

    async def _kill_object_tasks(self):
        mancomp: QwebTaskManager = await get_service(
            ServiceComponent.TASK, QwebTaskManager
        )
        insttasks = await mancomp.get_tasks_by_object(self.id)
        for task in insttasks:
            if task.running:
                if (
                    task.tasktype == PhasesSystemTask.PHASES_CLONE_FROM_APP.value
                    or task.tasktype == PhasesSystemTask.PHASES_CREATE_FROM_APP.value
                ):
                    self._log_info("Ommitting AUTOMATION TASKS")
                else:
                    task.task.cancel()

    @abstractmethod
    async def start(
        self, userid: int, connect: bool = False, object_mode: str = ""
    ) -> Optional[InstanceObject]:
        """Start the application."""
        raise NotImplementedError()

    @abstractmethod
    async def stop(self, instance: InstanceObject, force: bool) -> bool:
        """Stop and delete the instance."""
        raise NotImplementedError()
