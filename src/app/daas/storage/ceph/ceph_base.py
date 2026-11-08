"""Baseclass for ceph filestore"""

import os
import subprocess
import shutil
from typing import Optional
from app.daas.storage.ceph.ceph_config import CephstoreConfig
from app.qweb.logging.logging import LogTarget, Loggable

# Globals
CMD_LINUX_CEPH = "/usr/bin/ceph"
CMD_LINUX_MOUNT = "/usr/bin/mount"


class CephstoreBase(Loggable):
    """Baseclass for ceph filestore"""

    def __init__(self, config: CephstoreConfig):
        Loggable.__init__(self, LogTarget.FILES_LOCAL)
        self.config = config

    async def generate_ceph_conf_linux(self) -> str:
        """Returns configured ceph keyring folder (absolute)"""
        fsname = self.config.daasfs.name
        keydir = self.config.daasfs.folder_keyrings
        folder = os.path.abspath(f"{keydir}/{fsname}")
        cfgfile = f"{keydir}/{fsname}/ceph.conf"
        assert await self.__ensure_required_folder(folder)
        shutil.copyfile("/etc/ceph/ceph.conf", cfgfile)
        with open(cfgfile, "r", encoding="utf-8") as file:
            file_contents = file.read()
        file_contents = file_contents.replace(
            "keyring = /etc/pve/priv/$cluster.$name.keyring",
            "keyring = /etc/ceph/$cluster.$name.keyring",
        )
        with open(cfgfile, "w", encoding="utf-8") as file:
            file.write(file_contents)
        return folder

    async def get_ceph_folder(self) -> str:
        """Returns configured ceph folder (absolute)"""
        folder = os.path.abspath(self.config.daasfs.folder_mount)
        assert await self.__ensure_required_folder(self.config.daasfs.folder_mount)
        return folder

    async def get_ceph_folder_public(self) -> str:
        """Returns configured ceph public folder (absolute)"""
        fsname = self.config.daasfs.name
        mountdir = self.config.daasfs.folder_mount
        mountname = self.config.daasfs.folder_public
        folder = os.path.abspath(f"{mountdir}/{fsname}/{mountname}")
        assert await self.__ensure_required_folder(folder)
        return folder

    async def get_ceph_folder_shared(self) -> str:
        """Returns configured ceph shared folder (absolute)"""
        fsname = self.config.daasfs.name
        mountdir = self.config.daasfs.folder_mount
        mountname = self.config.daasfs.folder_shared
        folder = os.path.abspath(f"{mountdir}/{fsname}/{mountname}")
        assert await self.__ensure_required_folder(folder)
        return folder

    async def get_ceph_folder_user(self, userid: int = -1) -> str:
        """Returns configured ceph user folder (absolute)"""
        fsname = self.config.daasfs.name
        mountdir = self.config.daasfs.folder_mount
        mountname = self.config.daasfs.folder_user
        folder = os.path.abspath(f"{mountdir}/{fsname}/{mountname}")
        if userid != -1:
            folder = f"{folder}/{userid}"
        assert await self.__ensure_required_folder(folder)
        return folder

    async def get_ceph_folder_keyrings(self) -> str:
        """Returns configured ceph keyring folder (absolute)"""
        fsname = self.config.daasfs.name
        keydir = self.config.daasfs.folder_keyrings
        folder = os.path.abspath(f"{keydir}/{fsname}")
        assert await self.__ensure_required_folder(folder)
        return folder

    async def mount_ceph_folder(self) -> bool:
        src = await self.__get_source_token("admin", self.config.daasfs.name)
        dst = f"{self.config.daasfs.folder_mount}/{self.config.daasfs.name}"
        if await self.__ensure_required_folder(dst):
            mount_cmd = [CMD_LINUX_MOUNT, "-t", "ceph", src, dst]
            code, _, _ = await self.__run_cmd(mount_cmd)
            if code != 0:
                self._log_error(f"Exception on mount: {mount_cmd}")
                return False
            self._log_info(f"Mounted cephfs    : {src} to {dst}")
            assert await self.get_ceph_folder_public()
            assert await self.get_ceph_folder_shared()
            assert await self.get_ceph_folder_user()
            assert await self.get_ceph_folder_keyrings()
            return True
        return False

    async def __get_source_token(
        self,
        clientname: str,
        fsname: str,
    ) -> Optional[str]:
        code, fsid, str_err = await self.__run_cmd([CMD_LINUX_CEPH, "fsid"])
        if code != 0:
            self._log_error(f"Error on obtaining fsid: {str_err}")
            return None
        return f"{clientname}@{fsid.strip()}.{fsname}=/"

    async def __ensure_required_folder(self, folder: str) -> bool:
        if os.path.exists(folder) is False:
            os.makedirs(folder)
        assert os.path.exists(folder)
        return True

    async def __run_cmd(self, args: list) -> tuple:
        try:
            result = subprocess.run(
                args,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=True,
            )
            code = result.returncode
            str_out = result.stdout
            str_err = result.stderr
            return code, str_out, str_err
        except subprocess.CalledProcessError as ex:
            self._log_error(f"Exception on subprocess.run: {ex}")
            return -1, "", f"{ex}"
