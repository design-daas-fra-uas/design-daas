"""Baseclass for docker filestore"""

from typing import Optional
import os
import shutil
from app.daas.common.model import File
from app.daas.storage.local.fs_uploads import FilestoreUploads


class FilestoreDocker(FilestoreUploads):
    """Baseclass for docker filestore"""

    async def create_docker_envfile(
        self,
        objid: str,
        userid: int,
        imgname: str,
        envname: str,
        files: Optional[list[File]] = None,
        installers: Optional[list[str]] = None,
    ) -> str:
        """Copies specified Dockerfile into new environmental dockerfile"""
        files = files if files is not None else []
        installers = installers if installers is not None else []
        assert self.dbase is not None
        result = ""
        obj = await self.dbase.get_daas_object(objid)
        if obj is None:
            return ""
        dstfolder = await self.get_user_folder_docker(userid, imgname)
        dstfile = f"{dstfolder}/Dockerfile.{envname}"
        with open(dstfile, "w", encoding="UTF-8") as file:
            file.write(f"FROM daas.{imgname}\n")
            if len(files) > 0:
                file.write("\n# COPY FILES\n")
                for fileobj in files:
                    file.write(
                        f"COPY {fileobj.name} {fileobj.remotepath}/{fileobj.name}\n"
                    )
            if len(installers) > 0:
                file.write("\n# RUN INSTALLERS\n")
                for installer in installers:
                    file.write(f"RUN {installer}\n")

        result = dstfile
        assert os.path.exists(result)
        return result

    async def upload_user_envfile_docker(
        self,
        received_file,
        name: str,
        subdir: str,
        userid: int,
        files: Optional[list[File]] = None,
        installers: Optional[list[str]] = None,
    ) -> str:
        """
        Upload file to tmp folder
        """
        files = files if files is not None else []
        installers = installers if installers is not None else []
        folder = await self.get_user_folder_docker(userid, subdir)
        await self.upload_user_file(received_file, folder, f"Dockerfile.{name}", userid)
        dockerfile = await self.get_user_file_docker(subdir, userid, name)

        # Read the Dockerfile content
        await self.update_from_tag(dockerfile, subdir, userid, name)
        with open(dockerfile, "a", encoding="UTF-8") as file:
            if len(files) > 0:
                file.write("# COPY INSTALLERS\n")
                for fileobj in files:
                    file.write(
                        f"COPY {fileobj.name} {fileobj.remotepath}/{fileobj.name}\n"
                    )
            if len(installers) > 0:
                file.write("# RUN INSTALLERS\n")
                for installer in installers:
                    file.write(f"RUN {installer}\n")
        if len(files) > 0:
            for file in files:
                self._log_info(f"FILE: {file}")
        return dockerfile

    async def update_from_tag(
        self, dockerfile: str, subdir: str, userid: int, name: str
    ):
        """Updates from tag in dockerfile"""
        with open(dockerfile, "r", encoding="UTF-8") as file:
            dockerfile_content = file.read()
        lines = dockerfile_content.splitlines()
        new_dockerfile_content = []
        found_from_line = False
        subdir_lower = subdir.lower()
        newname = f"daas.{subdir_lower}"
        for line in lines:
            if line.strip().startswith("FROM"):
                new_dockerfile_content.append(f"FROM {newname}\n")
                found_from_line = True
            else:
                new_dockerfile_content.append(line)
        if found_from_line:
            with open(dockerfile, "w", encoding="UTF-8") as file:
                file.write("\n".join(new_dockerfile_content))
        self._log_info(f"Updated FROM tag for {name} (owner={userid})")

    async def get_docker_envfile(self, userid: int, imgname: str, envname: str) -> str:
        """
        Returns path to environmental dockerfile
        """

        dstfolder = await self.get_user_folder_docker(userid, imgname)
        return f"{dstfolder}/Dockerfile.{envname}"

    async def delete_docker_envfile(
        self, id: str, userid: int, imgname: str, envname: str
    ) -> str:
        """Deletes specified envfile"""
        assert self.dbase is not None
        result = ""
        obj = await self.dbase.get_daas_object(id)
        if obj is None:
            return ""
        dstfolder = await self.get_user_folder_docker(userid, imgname)
        dstfile = f"{dstfolder}/Dockerfile.{envname}"
        if os.path.exists(dstfile):
            os.remove(dstfile)
        assert os.path.exists(result) is False
        return result

    async def copy_root_dockerfile(
        self, imagename: str, userid: int, subdir: str
    ) -> str:
        """
        Copies specified root image
        """
        dstfolder = await self.get_user_folder_docker(userid, subdir)

        # Copy as template
        with open(f"{dstfolder}/Dockerfile", "w", encoding="UTF-8") as file:
            file.write(f"FROM {imagename}\n")

        assert os.path.exists(dstfolder)
        result = f"{dstfolder}/Dockerfile"
        assert os.path.exists(result)
        return result

    async def copy_user_dockerfile(
        self, dockerfile: str, userid: int, subdir: str
    ) -> str:
        """
        Copies specified dockerfile
        """
        dockerfolder = ""
        if os.path.exists(dockerfile) is False:
            return ""

        dockerfolder = os.path.dirname(dockerfile)
        dstfolder = await self.get_user_folder_docker(userid, subdir)

        if dockerfolder == dstfolder:
            shutil.copy(dockerfile, dstfolder)
        else:
            shutil.copytree(dockerfolder, dstfolder, dirs_exist_ok=True)

        assert os.path.exists(dstfolder)
        result = f"{dstfolder}/Dockerfile"
        assert os.path.exists(result)
        return result
