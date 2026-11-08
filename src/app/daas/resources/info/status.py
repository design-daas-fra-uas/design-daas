"""
Health of the whole stack for the admin status page (/monitoring/system_status).

Checks the same parts as `make status` in installer/: the DaaS backend
itself, the auth service (through its Spring actuator, /actuator/health),
the service containers the backend starts (container.toml: guacd, MariaDB,
RabbitMQ, extensions) and the frontend container.
"""

import os
from dataclasses import asdict, dataclass

import aiohttp

from app.daas.common.enums import BackendName
from app.daas.container.docker.DockerRequest import DockerRequest
from app.qweb.common.qweb_tools import get_backend_component
from app.qweb.common.tomlfile import read_toml_with_local
from app.qweb.logging.logging import LogTarget, Loggable

# Container of the frontend (installer/frontend/docker-compose.yml)
FRONTEND_CONTAINER = "daas-frontend"
# Version of this backend (the VERSION file of the repository)
VERSION_FILE = os.path.join(os.path.dirname(__file__), "../../../../../VERSION")

UP = "up"
DOWN = "down"
DISABLED = "disabled"


@dataclass
class ComponentStatus:
    """State of one part of the stack"""

    name: str
    kind: str
    state: str
    detail: str


class SystemStatusTool(Loggable):
    """Collects the ComponentStatus of every part of the stack"""

    def __init__(self, config_folder: str):
        Loggable.__init__(self, LogTarget.SYS)
        self.config_folder = config_folder

    async def collect(self) -> dict:
        """All components plus the overall state (up when all are up)"""
        components = [self._daas_status(), await self._auth_status()]
        components.extend(await self._container_status())
        down = [c.name for c in components if c.state == DOWN]
        if down:
            self._log_warn(f"System status: down: {', '.join(down)}")
        return {
            "state": DOWN if down else UP,
            "components": [asdict(c) for c in components],
        }

    def _daas_status(self) -> ComponentStatus:
        # This code answers, so the backend is up
        return ComponentStatus("daas", "service", UP, f"version {_read_version()}")

    async def _auth_status(self) -> ComponentStatus:
        auth = read_toml_with_local(f"{self.config_folder}/auth.toml").get("auth", {})
        if auth.get("authenticator_type") != "remote":
            return ComponentStatus("auth", "service", DISABLED, "local authentication")
        url = f"{auth['remote']['url']}/actuator/health"
        try:
            timeout = aiohttp.ClientTimeout(total=3)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(url) as response:
                    body = await response.json(content_type=None)
        except (aiohttp.ClientError, TimeoutError, ValueError) as exe:
            return ComponentStatus("auth", "service", DOWN, f"{url}: {exe}")
        health = body.get("status", "UNKNOWN") if isinstance(body, dict) else "UNKNOWN"
        state = UP if health == "UP" else DOWN
        return ComponentStatus("auth", "service", state, f"actuator health {health}")

    async def _container_status(self) -> list[ComponentStatus]:
        docker = await get_backend_component(BackendName.CONTAINER, DockerRequest)
        names = docker.service_container_names() + [FRONTEND_CONTAINER]
        result = []
        for name in names:
            container = await docker.docker_container_get(name)
            if container is None:
                result.append(ComponentStatus(name, "container", DOWN, "not found"))
                continue
            state = UP if container.status == "running" else DOWN
            image = container.image.tags[0] if container.image.tags else "?"
            result.append(
                ComponentStatus(
                    name, "container", state, f"{container.status}, {image}"
                )
            )
        return result


def _read_version() -> str:
    try:
        with open(VERSION_FILE, encoding="utf-8") as pointer:
            return pointer.read().strip()
    except OSError:
        return "unknown"
