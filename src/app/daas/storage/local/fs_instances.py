""" Baseclass for instance filestore"""

import os
from app.daas.common.model import File, Instance
from app.daas.storage.local.fs_permissions import FilestorePermissions
from app.daas.storage.local.fs_config import FilestoreConfig
from app.qweb.common.qweb_tools import get_database

CMD_LINUX_CHMOD = "/usr/bin/chmod"
CMD_LINUX_XTERM = "/usr/bin/xterm"
CMD_LINUX_MKDIR = "mkdir"
CMD_LINUX_READFILE = "cat"
CMD_WIN_CMD = "cmd.exe"
CMD_WIN_MKDIR = "/c mkdir -p"
CMD_WIN_READFILE = "type"


class FilestoreInstances(FilestorePermissions):
    """Baseclass for instance filestore"""

    def __init__(self, config: FilestoreConfig):
        super().__init__(config)

    async def read_inst_file_status(
        self, adr: str, windows: bool, os_username: str
    ) -> tuple:
        """Read results from cmdline invocations"""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        instance = await dbase.get_instance_by_adr(adr)
        cmd = CMD_WIN_READFILE
        if instance is not None:
            if not windows:
                cmd = CMD_LINUX_READFILE
            statusfile = await self.get_inst_file_status(os_username, windows, False)
            ret = await instance.inst_vminvoke_ssh(cmd=cmd, args=f"{statusfile}")
            if ret is not None and ret.response_code == 200:
                return 0, ret.sys_log, ""
        return 1, "", "No instance"

    async def upload_file_to_instance(self, file: File, instance: Instance) -> bool:
        """Upload file to tmp folder"""
        srcfile = file.localpath
        dstfile = file.remotepath

        windows = False
        if instance.app.os_type in ("win10", "win11"):
            windows = True
        return await self.__upload_inst_file(
            adr=instance.host,
            filename=srcfile,
            folder=dstfile,
            windows=windows,
            remote_name=file.name,
        )

    async def get_inst_file_status(
        self, os_username: str, windows: bool, relative: bool
    ) -> str:
        """
        Returns absolute filename within instance
        """
        name = self.config.instance_status_outfile_name
        folder = await self.__get_inst_folder_status(os_username, windows, relative)
        return await self.__get_inst_file(name, folder, windows)

    async def __get_inst_folder_daas(
        self, os_username: str, windows: bool, relative: bool
    ) -> str:
        if relative:
            return "daas"
        if windows:
            return f"C:\\Users\\{os_username}\\daas"
        if os_username == "root":
            return f"/{os_username}/daas"
        return f"/home/{os_username}/daas"

    async def __get_inst_folder_status(
        self, os_username: str, windows: bool, relative: bool
    ) -> str:
        daas_folder = await self.__get_inst_folder_daas(os_username, windows, relative)
        folder = f"{daas_folder}/{self.config.folder_inst_status}"
        if windows:
            folder = f"{daas_folder}\\{self.config.folder_inst_status}"
        return folder

    async def __get_inst_file(
        self,
        name: str,
        folder: str,
        windows: bool,
    ) -> str:
        """
        Returns absolute filename within instance
        """
        if windows:
            return f"{folder}\\{name}"
        return f"{folder}/{name}"

    async def get_filename_instance(
        self, filename: str, windows: bool, remote_name: str = ""
    ) -> str:
        result = ""
        DEFAULT_INST_PATH_WIN = "C:/Users/root/daas"
        DEFAULT_INST_PATH_LINUX = "/root/daas"
        folder = DEFAULT_INST_PATH_LINUX
        if windows:
            folder = DEFAULT_INST_PATH_WIN

        name = os.path.basename(filename)
        result = f"{folder}/{name}"
        if remote_name != "":
            result = f"{folder}/{remote_name}/{name}"
        return result

    async def __upload_inst_file(
        self, adr: str, filename: str, folder: str, windows: bool, remote_name: str = ""
    ) -> bool:
        """
        Upload file to instance
        """
        from app.daas.db.database import Database

        dbase = await get_database(Database)

        result = False
        instance = await dbase.get_instance_by_adr(adr)

        if instance is not None:
            if os.path.exists(filename) is False:
                return False
            name = os.path.basename(filename)
            norm_folder = f"{folder}/{name}"
            if remote_name != "":
                norm_folder = f"{folder}/{remote_name}"
            if windows:
                if remote_name != "":
                    norm_folder = f"{folder}/{remote_name}"
                else:
                    norm_folder = f"{folder}/{name}"
            ret = await instance.inst_vminvoke_upload(
                filename, instance.app.os_type in ("win10", "win11"), False
            )
            if ret is not None and ret.response_code == 200:
                result = True
        return result
