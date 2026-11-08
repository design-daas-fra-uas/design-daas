"""Task to create objects within a background task"""

from app.daas.tasks.base_clonetask import CloneTaskBase


class CreateTask(CloneTaskBase):
    """Builds a new base image from an application (see CloneTaskBase)"""

    kind = "Create"
