"""Extra data model definitions."""

from __future__ import annotations
from dataclasses import dataclass
from typing import Optional
from abc import ABC
from datetime import datetime
from app.daas.db.db_mappings import (
    ORMMappingType,
    ORMModelDomain,
)
from app.qweb.logging.logging import LogTarget, Loggable


class DaaSEntity(ABC, Loggable):
    __orm_etype = ORMMappingType.Unknown

    def __init__(self):
        Loggable.__init__(self, LogTarget.OBJECT)

    def get_data(self):
        data = vars(self)
        if "logger" in data:
            data.pop("logger")
        if "log_target" in data:
            data.pop("log_target")
        return data


@dataclass
class DaasObject(DaaSEntity):
    """
    An application configuration or container or VM that can be launched.
    """

    id: str
    """An unique identifier for this app – should be UUID."""

    id_user: str
    """An arbitrary specification given by the user"""

    id_owner: int
    """The owner id"""

    id_proxmox: int
    """
    An unique identifier used by the proxmox backend.
    """
    id_docker: str
    """
    An unique identifier used by the docker backend.
    """

    object_type: str
    """Type of object"""

    object_mode: str
    """Current mode of operation"""

    object_mode_extended: str
    """Current submode of operation"""

    object_state: str
    """Current object state"""

    object_tasks: list
    """Current object tasks"""

    object_apps: list
    """Current object applist"""

    object_target: dict
    """Current object target"""

    object_storage: str
    """object data storage location"""

    os_wine: bool
    """Has wine capabilities"""

    os_type: str
    """Type of operating system"""

    hw_cpus: int
    """Amount of cpus"""

    hw_memory: int
    """Amount of memory in bytes"""

    hw_disksize: int
    """Amount of bytes on disk"""

    os_username: str = "root"
    """Username within the installed os"""

    os_password: str = "root"
    """Password within the installed os"""

    os_installer: str = ""
    """The initial image the object is based on"""

    ceph_public: bool = True
    """Public cephfs share"""

    ceph_shared: bool = True
    """Shared cephfs share"""

    ceph_user: bool = True
    """User cephfs share"""

    vnc_port_system: int = -1
    """The port used for default vnc connections"""

    vnc_port_instance: int = 5900
    """The port used for connections directly initiated against the instance"""

    vnc_username: str = "user1234"
    """The username used for vnc connections"""

    vnc_password: str = "user1234"
    """The password used for vnc connections"""

    viewer_contype: str = "sysvnc"
    """Connection protocol for viewer"""

    viewer_resolution: str = "1280x800"
    """Default resolution"""

    viewer_resize: str = "both"
    """Resize method"""

    viewer_scale: str = "both"
    """Scale method"""

    viewer_dpi: int = 96
    """Viewer dpi"""

    viewer_colors: int = 32
    """Viewer color depth"""

    viewer_force_lossless: bool = False
    """Force viewer to use lossless compression if applicable"""

    extra_args: str = ""
    """Optional arguments"""

    def __repr__(self):
        return (
            f"{self.__class__.__qualname__}"
            f"(id={self.id},name={self.id_user},"
            f"obj_type={self.object_type},os_type={self.os_type})"
        )


@ORMModelDomain(ORMMappingType.File)
@dataclass
class File(DaaSEntity):
    """A uploadable file object"""

    id: str
    """Unique ID for this application"""

    id_owner: int
    """Unique ID for the owning user or -1 for a global application"""

    name: str
    """Name of the application"""

    version: str
    """The applicatiuon version"""

    os_type: str
    """The type of operating system"""

    localpath: str
    """The local path opf the file"""

    remotepath: str
    """The remote path opf the file"""

    filesize: int
    """The filesize in bytes"""

    created_at: datetime
    """When this application was first created."""

    def __repr__(self):
        return (
            f"{self.__class__.__qualname__}"
            f"(id={self.id},name={self.name},os_type={self.os_type})"
        )


@dataclass
class Application(DaaSEntity):
    """A configurable application object"""

    id: str
    """Unique ID for this application"""

    id_owner: int
    """Unique ID for the owning user or -1 for a global application"""

    name: str
    """Name of the application"""

    version: str
    """The applicatiuon version"""

    id_file: Optional[str]
    """The id of the file to copy"""

    id_template: Optional[str]
    """The id of the source object for cloning"""

    os_type: str
    """The type of operating system"""

    installer: str
    """The related installer path"""

    installer_args: str
    """Installer arguments"""

    installer_type: str
    """The related installer type"""

    target: str
    """The installed executable path"""

    target_args: str
    """executable args"""

    created_at: datetime
    """When this application was first created."""

    def __repr__(self):
        return (
            f"{self.__class__.__qualname__}"
            f"(id={self.id},name={self.name},os_type={self.os_type})"
        )


@ORMModelDomain(ORMMappingType.Environment)
@dataclass
class Environment(DaaSEntity):
    """An environment derived from a daas_object"""

    id: str
    """Unique ID for this environemnt."""

    id_backend: str
    """Unique ID for the latest snapshot."""

    id_object: str
    """key to Object configuration that is being instantiated."""

    name: str
    """Name of the environment."""

    state: str
    """State of the environment."""

    env_tasks: list
    """Current env tasks"""

    env_apps: list
    """Current env applist"""

    env_target: dict
    """Current env target"""

    created_at: datetime
    """When this environment was first created."""

    def __repr__(self):
        return f"{self.__class__.__qualname__}" f"(id={self.id},name={self.name})"


@dataclass
class Instance(DaaSEntity):
    """An instance of some application"""

    id: str
    """Unique ID for this instance."""

    id_owner: int
    """Id of the owner"""

    app: DaasObject
    """App configuration that is being instantiated."""

    host: str
    """
    Local available Ip or resolvable hostname assigned by backend services
    """

    container: str
    """
    Container short_id assigned by docker backend
    """

    created_at: datetime
    """When this instance was first created."""

    connected_at: datetime
    """When this instance was first connected."""

    booted_at: datetime
    """When this instance was first connected."""

    id_con: Optional[str]
    """Connection"""

    id_app: str  # Optional[str]
    """App id"""

    id_env: Optional[str]
    """Env id"""

    env: Optional[Environment] = None
    """Environment configuration that is being instantiated."""

    def __repr__(self):
        return f"{self.__class__.__qualname__}" f"(id={self.id})"


@ORMModelDomain(ORMMappingType.GuacamoleConnection)
@dataclass(kw_only=True)
class GuacamoleConnection(DaaSEntity):
    """
    Connection details for Guacamole.
    """

    id: str
    """Unique ID"""

    user: str
    """Username for the connection auth."""

    password: str
    """Password for the connection auth."""

    protocol: str
    """Protocol used by guacd, either `vnc` or `rdp`."""

    hostname: str
    """Hostname where guacd can find the connection's server."""

    port: int
    """Port where guacd can find the connection's server."""

    viewer_url: str
    """Absolute Endpoint URL for this connection"""

    viewer_token: str
    """Authentication token for this connection"""

    def __repr__(self):
        return f"{self.__class__.__qualname__}" f"(id={self.id})"


@ORMModelDomain(ORMMappingType.Limit)
@dataclass
class RessourceInfo(DaaSEntity):
    """Ressource limits"""

    id_owner: int
    vm_max: int
    container_max: int
    obj_max: int
    cpu_max: int
    mem_max: int
    dsk_max: int

    def add(self, other):
        """Adds other ressources"""
        self.vm_max += other.vm_max
        self.container_max += other.container_max
        self.obj_max += other.obj_max
        self.cpu_max += other.cpu_max
        self.mem_max += other.mem_max
        self.dsk_max += other.dsk_max

    def __repr__(self) -> str:
        return (
            f"{self.__class__.__qualname__}"
            f"(id_owner={self.id_owner},"
            f"objs=({self.obj_max},{self.vm_max},{self.container_max}),"
            f"res=({self.cpu_max},{self.mem_max},{self.dsk_max})"
            ")"
        )
