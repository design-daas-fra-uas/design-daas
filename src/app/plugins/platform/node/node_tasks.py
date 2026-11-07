"""Node Tasks"""

from enum import Enum
from app.daas.common.ctx import get_backend_component, get_request_object
from app.daas.node.nodecontrol import NodeController
from app.daas.objects.object_instance import InstanceObject
from app.qweb.common.common import TaskArgs
from app.qweb.processing.processor import QwebResult


class NodeTask(Enum):
    """Node processor tasktype"""

    NODE_CONFIGURE_DHCP = "NODE_CONFIGURE_DHCP"
    NODE_CONFIGURE_IPTABLES = "NODE_CONFIGURE_IPTABLES"
    NODE_INVOKE_UPLOAD = "NODE_INVOKE_UPLOAD"


async def configure_dhcp(args: TaskArgs) -> QwebResult:
    """Configure dhcp"""
    entity = get_request_object(args.ctx, "entity", InstanceObject)
    nodecon = get_backend_component(args.ctx, "node", NodeController)
    code, str_out, str_err = await nodecon.node_vmconfigure_dhcp(
        entity.app.id_proxmox, entity.host
    )
    return _create_result(code, f"{str_out}{str_err}")


async def configure_iptables(args: TaskArgs) -> QwebResult:
    """Configure iptables"""
    entity = get_request_object(args.ctx, "entity", InstanceObject)
    nodecon = get_backend_component(args.ctx, "node", NodeController)
    code, str_out, str_err = await nodecon.node_vmconfigure_iptables(entity.host)
    return _create_result(code, f"{str_out}{str_err}")


async def invoke_upload(_args: TaskArgs) -> QwebResult:
    """Upload a file to the host (not implemented)"""
    return QwebResult(501, {}, 1, "invoke_upload is not implemented")


def _create_result(code: int, syslog: str) -> QwebResult:
    if code == 0:
        return QwebResult(200, {}, code, syslog)
    return QwebResult(400, {}, code, syslog, error_message="node command failed")
