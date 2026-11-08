"""
This module defines the RpcClient class, which handles sending RPC requests to online hosts.
It uses the HeartbeatServer to verify the availability of instances before sending messages.
"""

from dataclasses import asdict, dataclass
from typing import Optional
import threading
import json
import time
import logging
import uuid
import pika

from app.daas.messaging.qmsg.common.qmsg_model import RpcRequest, RpcResponse


@dataclass
class RpcSenderConfig:
    """
    Configuration dataclass for RpcServer.
    Holds the RabbitMQ connection details and operational parameters.
    """

    rabbitmq_host: str = "10.23.42.7"
    reconnect_time: int = 5
    wait_time_ms: int = 100
    wait_time_total_ms: int = 30000
    log_topic: str = "daas.adapter.qmsg"


class RpcSender:
    """
    The RpcSender class handles sending remote procedure calls (RPC) to online hosts.
    """

    def __init__(self, config: RpcSenderConfig) -> None:
        """
        Initialize the RpcClient with the provided RabbitMQ connection details.
        """
        self.config = config
        self.result = None
        self.corr_id = ""
        self.waiting = False
        self.response = None
        self.logger = logging.getLogger(self.config.log_topic)
        self.connection: Optional[pika.BlockingConnection] = None
        self.channel: Optional[pika.channel.Channel] = None
        self.thread: Optional[threading.Thread] = None
        self.callback_queue = ""

    def connect(self) -> None:
        """
        Establish a connection to RabbitMQ with one reply queue for all calls
        of this sender. If the connection fails, retry after a delay.
        """
        while True:
            try:
                self.connection = pika.BlockingConnection(
                    pika.ConnectionParameters(host=self.config.rabbitmq_host)
                )
                self.channel = self.connection.channel()
                self.callback_queue = self.channel.queue_declare(
                    queue="", exclusive=True
                ).method.queue
                self.channel.basic_consume(
                    queue=self.callback_queue,
                    on_message_callback=self.on_response,
                    auto_ack=True,
                )
                break
            except pika.exceptions.AMQPConnectionError as exe:
                self.__log_error(
                    (
                        "Connection failed, "
                        f"retrying in {self.config.reconnect_time} seconds... "
                        f"Error: {exe}"
                    )
                )
                time.sleep(self.config.reconnect_time)

    def close(self) -> None:
        """Close the connection (also when the broker is already gone)"""
        if self.connection is not None and self.connection.is_open:
            try:
                self.connection.close()
            # pika raises AssertionError when its transport is already broken
            except (pika.exceptions.AMQPError, AssertionError) as exe:
                self.__log_error(f"Error on close: {exe}")
        self.connection = None
        self.channel = None

    def on_response(self, channel, method, props, body):
        """Called on response"""
        if self.corr_id == props.correlation_id:
            raw_dict = json.loads(body.decode())
            self.response = RpcResponse(**raw_dict)
            self.waiting = False

    def call_rpc_method(self, queue_name: str, msg: RpcRequest) -> threading.Thread:
        """
        Run the RPC request in a separate thread (one call, then the
        connection is closed).
        """
        self.__log_info(f"Create RpcRequest thread for {msg}")
        self.thread = threading.Thread(
            target=self.__call_rpc_method, args=[queue_name, msg]
        )
        self.thread.start()
        return self.thread

    def __call_rpc_method(
        self, queue_name: str, msg: RpcRequest
    ) -> Optional[RpcResponse]:
        try:
            return self.call(queue_name, msg)
        finally:
            self.close()

    def call(self, queue_name: str, msg: RpcRequest) -> Optional[RpcResponse]:
        """
        Send an RPC request to the specified queue and wait for the answer.
        Reuses this sender's connection (one sender per thread: pika
        connections are not thread-safe).
        """
        self.corr_id = str(uuid.uuid4())
        self.response = None
        try:
            self.waiting = True
            if not self.__publish(queue_name, msg):
                return None
            what = _describe(msg)
            total_s = self.config.wait_time_total_ms // 1000
            self.__log_info(f"Sent to {queue_name}: {what}")
            started = time.monotonic()
            next_report = 30
            while time.monotonic() - started < total_s:
                self.connection.process_data_events()
                if self.waiting is False:
                    self.__log_answer(queue_name, what, int(time.monotonic() - started))
                    return self.response
                time.sleep(self.config.wait_time_ms / 1000)
                waited = int(time.monotonic() - started)
                if waited >= next_report:
                    self.__log_info(
                        f"Waiting for {queue_name}: {what} ({waited} s of {total_s} s)"
                    )
                    next_report += 30
            self.__log_error(
                f"No answer from {queue_name} after {total_s} s: {what} "
                "(raise inst_queue.wait_time_total_ms in config/messaging.toml "
                "if the command needs longer)"
            )
            return None
        except Exception as exe:
            self.__log_error(f"Failed to send RPC call. Error: {exe}")
            self.close()
        finally:
            self.waiting = False
        return None

    def __publish(self, queue_name: str, msg: RpcRequest) -> bool:
        """
        Publishes msg, reconnecting once when the connection is broken: an
        idle connection processes no heartbeats, so the broker drops it after
        a while. Only publishing is retried, never waiting for the answer, so
        a command never runs twice.
        """
        for _ in range(2):
            if self.connection is None or not self.connection.is_open:
                self.connect()
            try:
                self.channel.basic_publish(
                    exchange="",
                    routing_key=queue_name,
                    properties=pika.BasicProperties(
                        reply_to=self.callback_queue,
                        correlation_id=self.corr_id,
                    ),
                    body=json.dumps(asdict(msg)),
                )
                return True
            except pika.exceptions.AMQPConnectionError as exe:
                # Expected after idle time; only failing twice is an error
                self.__log_info(f"Connection closed by RabbitMQ, reconnecting: {exe}")
                self.close()
        self.__log_error(f"Failed to send RPC call to {queue_name}: {msg}")
        return False

    def __log_answer(self, queue_name: str, what: str, waited: int):
        result = self.response.processor_result if self.response else {}
        code = result.get("code", "?") if isinstance(result, dict) else "?"
        line = f"Answer from {queue_name} after {waited} s: {what} -> exit code {code}"
        if code == 0:
            self.__log_info(line)
        else:
            err = str(result.get("std_err", "")).strip()[-300:]
            self.__log_error(f"{line}: {err}")
        # The full output (e.g. all apt lines) only on debug level
        self.logger.debug(f"  QMSG: full answer: {self.response}")

    def __log_info(self, msg: str, code: int = 0):
        msg = f"  QMSG: {code:3} -> {msg}"
        self.logger.info(msg)

    def __log_error(self, msg: str, code: int = 1):
        msg = f"  QMSG: {code:3} -> {msg}"
        self.logger.error(msg)


def _describe(msg: RpcRequest) -> str:
    """Short form of a request for the log, e.g. "ospackage install firefox-esr" """
    args = " ".join(a for a in msg.request_args if a)
    return f"{msg.request_type} {msg.request_cmd} {args}".strip()
