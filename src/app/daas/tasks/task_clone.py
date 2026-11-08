"""Task to clone objects within a background task"""

import asyncio
from app.daas.tasks.base_clonetask import CloneTaskBase


class CloneTask(CloneTaskBase):
    """Builds an application on a clone of a base image (see CloneTaskBase)"""

    kind = "Clone"

    async def _wait_for_baseimage_boot(self):
        """The clone is polled directly until its agent answers"""
        online = await self.inst.check_online_state()
        waited = 0
        while not online:
            online = await self.inst.check_online_state()
            await asyncio.sleep(1)
            waited += 1
            if waited % 60 == 0:
                self._log_info(
                    f"Still waiting for {self.inst.host or self.inst.id} to boot: "
                    f"{waited // 60} min"
                )
