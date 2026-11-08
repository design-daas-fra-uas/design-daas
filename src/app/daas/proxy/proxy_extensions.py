"""Proxy extensions"""

import subprocess
import asyncio
from websockets.asyncio.client import ClientConnection
from datetime import datetime
from dataclasses import dataclass, replace
from quart import Websocket
from app.daas.adapter.adapter_ssh import SshAdapter
from app.daas.common.enums import BackendName
from app.daas.container.docker.DockerRequest import DockerRequest
from app.daas.proxy.proxy_registry import ProxyRegistry
from app.plugins.platform.messaging.messaging_backend import MessagingBackend
from app.qweb.common.qweb_tools import get_backend, get_backend_component, get_database
from app.qweb.logging.logging import LogTarget, Loggable
from app.daas.objects.object_instance import InstanceObject
from app.daas.common.model import GuacamoleConnection
from app.daas.proxy.guacamole_proxy import SocketTuple, WebsocketStats


@dataclass
class ProxyExtensionsConfig:
    """Config for ProxyExtensions"""

    displayname: str
    prefix_printer_user: str
    service_ip: str
    service_port_cups: int
    service_port_audio: int
    service_port_printer: int
    service_proto_printer: str
    service_container: str
    update_service_ip: bool


class ProxyExtensions(Loggable):
    """Proxy extensions"""

    def __init__(self, cfg: ProxyExtensionsConfig):
        Loggable.__init__(self, LogTarget.PROXY)
        self.connected = False
        self.config = cfg

    def connect(self):
        """Connects the component"""
        self.connected = True
        return self.connected

    def disconnect(self) -> bool:
        """Disconnects the component"""
        self.connected = False
        return True

    async def create_audio_socket(self, inst: InstanceObject) -> subprocess.Popen:
        """creates socket for microphone stream"""
        return subprocess.Popen(
            [
                "pacat",
                f"--server={inst.host}:{self.config.service_port_audio}",
                "--channels=1",
                "--latency-msec=1",
            ],
            stdin=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    async def proxy_audio_socket(
        self,
        conid: str,
        inst: InstanceObject,
        con: GuacamoleConnection,
        client_ws: Websocket,
        audio_proc: subprocess.Popen,
    ):
        """Proxies incoming websocket data to instance microphone sink"""
        reg = await get_backend_component(BackendName.PROXY, ProxyRegistry)
        new_tuple = await self._create_socket_tuple(
            conid, inst, con, audio_proc, client_ws
        )
        reg.add_connection(new_tuple)

        try:
            while audio_proc.stdin is not None:
                data = await asyncio.wait_for(client_ws.receive(), timeout=3.0)
                if isinstance(data, str):
                    if data == "close":
                        self._log_info(f"Closing audio connection {conid}")
                        break
                    continue
                audio_proc.stdin.write(data)
                audio_proc.stdin.flush()
        except Exception as exe:  # pylint: disable=broad-exception-caught
            self._log_warn(f"Audio connection {conid} ended: {exe!r}")
        finally:
            # Also runs when the client disconnects (CancelledError)
            if audio_proc.stdin:
                try:
                    audio_proc.stdin.close()
                except OSError:
                    pass
            audio_proc.terminate()
            reg.disconnect_connection(conid)
            self._log_info(f"Exit audio socket loop {conid}")

    async def proxy_printer_sockets(
        self,
        conid: str,
        inst: InstanceObject,
        con: GuacamoleConnection,
        client_ws: Websocket,
        backend_ws: ClientConnection,
    ):
        """Proxifies client_ws and backend_ws"""
        reg = await get_backend_component(BackendName.PROXY, ProxyRegistry)
        new_tuple = await self._create_socket_tuple(
            conid, inst, con, backend_ws, client_ws
        )
        reg.add_connection(new_tuple)

        async def from_browser_to_service():
            """Receive messages from client and send them to backend WebSocket."""
            while True:
                message = await client_ws.receive()
                if message == "close":
                    self._log_info(f"Closing printer connection {conid}")
                    return
                await backend_ws.send(message)

        async def from_service_to_browser():
            """Receive messages from backend WebSocket and send them to client."""
            async for message in backend_ws:
                await client_ws.send(message)

        self._log_info(f"Establishing new printer connection {conid}")
        tasks = {
            asyncio.create_task(from_browser_to_service()),
            asyncio.create_task(from_service_to_browser()),
        }
        try:
            # Runs until one direction ends (or the client disconnects)
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                if task.exception() is not None:
                    self._log_warn(
                        f"Printer connection {conid} ended: {task.exception()!r}"
                    )
            await client_ws.close(1000, "Closed")
        except RuntimeError:
            pass  # the client websocket is already closed
        finally:
            for task in tasks:
                task.cancel()
            await backend_ws.close()
            reg.disconnect_connection(conid)
            self._log_info(f"Exit printer socket loop {conid}")

    async def add_printer_service(self, host: str, owner: int):
        """Adds printer for specified user"""
        cmd, args = await self._get_create_printer_params(owner)

        adapter = await self._create_service_adapter()

        fullcmd = f"{cmd}{args}"
        code, strout, strerr = adapter.ssh_call(fullcmd)
        if code != 0:
            self._log_error(f"Error adding service: {strout}{strerr}")
            return False
        return True

    async def add_printer_instance(self, host: str, owner: int, iswin: bool):
        """Adds printer for specified user instance"""
        from app.daas.db.database import Database

        dbase = await get_database(Database)
        instance = await dbase.get_instance_by_adr(host)
        if instance is None:
            return False

        if iswin is False:
            check_cmd, check_args = await self._get_linux_printercheck_params()
        else:
            check_cmd, check_args = await self._get_windows_printercheck_params()
        ret = await instance.inst_vminvoke_ssh(check_cmd, check_args)
        if ret.response_code == 200 and ret.sys_log != "":
            self._log_info(f"Printer exists: {ret.sys_log}")

        if iswin is False:
            cmd, args = await self._get_linux_params(owner)
        else:
            cmd, args = await self._get_windows_params(owner)

        ret = await instance.inst_vminvoke_ssh(cmd, args)
        if ret.response_code != 200:
            self._log_error(f"Error adding instance: {ret.sys_log}")
            return False
        return True

    async def get_url_service_printer(self) -> str:
        """Returns service url for printer"""
        host = self.config.service_ip
        if host == "":
            host = await self._get_service_ip(self.config.update_service_ip)
        return (
            f"{self.config.service_proto_printer}"
            f"{host}:{self.config.service_port_printer}/vnc/printer"
        )

    async def _create_socket_tuple(
        self,
        conid: str,
        inst: InstanceObject,
        con: GuacamoleConnection,
        service,
        client,
    ):
        return SocketTuple(
            conid,
            conid,
            inst.app.id_owner,
            service,
            client,
            con,
            datetime.now(),
            datetime.now(),
            WebsocketStats(),
        )

    async def _get_linux_params(self, owner: int) -> tuple[str, str]:
        cmd = "lpadmin"
        port = self.config.service_port_cups
        printername = f"{self.config.prefix_printer_user}{owner}"
        serviceip = self.config.service_ip
        if serviceip == "":
            serviceip = await self._get_service_ip(self.config.update_service_ip)
        url = f"ipp://{serviceip}:{port}/printers/{printername}"
        name = self.config.displayname
        # Replace an old printer, add it, and make it the default destination
        args = f"-x {name} ; lpadmin -p {name} -E -v {url} && lpadmin -d {name}"
        return cmd, args

    async def _get_windows_params(self, owner: int) -> tuple[str, str]:
        cmd = "rundll32"
        port = self.config.service_port_cups
        printername = f"{self.config.prefix_printer_user}{owner}"
        serviceip = self.config.service_ip
        if serviceip == "":
            serviceip = await self._get_service_ip(self.config.update_service_ip)
        url = f"http://{serviceip}:{port}/printers/{printername}"
        args = (
            "printui.dll,PrintUIEntry "
            f'/if /b "{self.config.displayname}" /r "{url}" /m "Generic / Text Only" /z'
        )
        return cmd, args

    async def _get_linux_printercheck_params(self) -> tuple[str, str]:
        return "lpstat", f"-p {self.config.displayname}"

    async def _get_windows_printercheck_params(self) -> tuple[str, str]:
        return "wmic", f'printer get name | findstr /I "{self.config.displayname}"'

    async def _get_create_printer_params(self, owner: int) -> tuple[str, str]:
        cmd = "cd"
        srcdir = "/usr/src/app"
        printername = f"{self.config.prefix_printer_user}{owner}"
        args = f" {srcdir} && ./scripts/create_printer.sh {printername}"
        return cmd, args

    async def _create_service_adapter(self) -> SshAdapter:
        """Create Adapter for a specific instance"""
        serviceip = self.config.service_ip
        if serviceip == "":
            serviceip = await self._get_service_ip(self.config.update_service_ip)
        hub = await get_backend(BackendName.MESSAGING, MessagingBackend)
        cfg = replace(hub.cfg_ssh, sshhost=serviceip)
        return SshAdapter(cfg)

    async def _get_service_ip(self, update: bool) -> str:
        """Returns ip of configured  service container"""
        api = await get_backend_component(BackendName.CONTAINER, DockerRequest)
        result = await api.docker_get_container_ip(self.config.service_container)
        if update is True:
            self.config.service_ip = result
        return result
