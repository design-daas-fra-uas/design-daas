"""DB Tasks"""

from dataclasses import asdict, is_dataclass
from enum import Enum
from app.qweb.common.common import TaskArgs


class TestTask(Enum):
    """Test processor tasktype"""

    TEST_GET_ENTITY = "TEST_GET_ENTITY"


async def test_get_layer_entity(args: TaskArgs) -> dict:
    """Returns the requested layer object as dict"""
    req_objects = args.ctx.objects.objects
    if "entity" in req_objects:
        entity = req_objects["entity"]
        if isinstance(entity, dict):
            return entity
        if is_dataclass(entity) and not isinstance(entity, type):
            return asdict(entity)
    return {"Error": "Unknown error"}
