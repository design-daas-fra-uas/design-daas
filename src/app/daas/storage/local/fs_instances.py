"""Baseclass for instance filestore"""

import os
from app.daas.storage.local.fs_permissions import FilestorePermissions
from app.qweb.common.qweb_tools import get_database

CMD_LINUX_READFILE = "cat"
CMD_WIN_READFILE = "type"
INST_PATH_WIN = "C:/Users/root/daas"
INST_PATH_LINUX = "/root/daas"


class FilestoreInstances(FilestorePermissions):
    """Baseclass for instance filestore"""

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
        """Returns the path of filename in the instance's daas folder"""
        folder = INST_PATH_WIN if windows else INST_PATH_LINUX
        name = os.path.basename(filename)
        result = f"{folder}/{name}"
        if remote_name != "":
            result = f"{folder}/{remote_name}/{name}"
        return result
