"""
Provide state management via the ``Database`` class.
"""

from __future__ import annotations
import logging
from app.daas.common.enums import ConfigFile, ConfigSections
from app.daas.db.db_samples import SampleRegistry, SampleRegistryConfig
from app.daas.objects.object_application import ApplicationObject
from app.qweb.logging.logging import LogTarget
from app.daas.db.db_repos import (
    ApplicationRepository,
    ConnectionRepository,
    EnvironmentRepository,
    FileRepository,
    InstanceRepository,
    LimitRepository,
    ObjectRepository,
)


class Database(
    LimitRepository,
    FileRepository,
    ApplicationRepository,
    ConnectionRepository,
    EnvironmentRepository,
    ObjectRepository,
    InstanceRepository,
):
    """
    A wrapper for database operations.
    Uses SQLAlchemy (ORM) for storing state.
    """

    async def connect(
        self,
    ) -> Database:
        """Connects database"""
        self.connected = await self._connect()
        return self

    async def disconnect(self) -> None:
        """Disconnects database"""
        await self._disconnect()

    async def load_demo_apps(self) -> None:
        """
        Prime the database with some apps
        that are known to be available for a demo.
        """
        from app.daas.objects.object_container import ContainerObject
        from app.daas.objects.object_machine import MachineObject

        cfg = await self._get_config_samples()
        logger = logging.getLogger(LogTarget.DB.value)
        registry = SampleRegistry(cfg=cfg)

        limitlist = registry.create_demo_limits()
        for testlimit in limitlist:
            if not await self.get_limit(testlimit.id_owner):
                logger.info("Import limit      : (%s)", testlimit.id_owner)
                await self.create_limit(testlimit)

        filelist = registry.create_demo_files()
        for testfile in filelist:
            if not await self.get_file(testfile.id):
                logger.info("Import file       : %s (%s)", testfile.name, testfile.id)
                await self.create_file(testfile)

        objlist = registry.create_demo_objects()
        for obj in objlist:
            if isinstance(obj, (ContainerObject, MachineObject)):
                if not await self.get_daas_object(obj.id):
                    logger.info("Import object     : %s (%s)", obj.id_user, obj.id)
                    await self.create_daas_object(obj)

        applist = registry.create_demo_applications()
        for testapp in applist:
            if isinstance(testapp, ApplicationObject):
                if not await self.get_application(testapp.id):
                    logger.info("Import application: %s (%s)", testapp.name, testapp.id)
                    await self.create_application(testapp)

    async def _get_config_samples(self) -> SampleRegistryConfig:
        dictconf = await self._get_config(ConfigFile.DB.value)
        return SampleRegistryConfig(**dictconf[ConfigSections.SAMPLES.value])
