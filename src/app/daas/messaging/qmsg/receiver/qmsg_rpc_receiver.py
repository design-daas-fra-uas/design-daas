"""
This module defines the RpcServer class, which listens for and executes RPC requests
sent by the server. It handles reconnection if the connection is lost.

The connection is opened, consumed and closed in one thread (thread_listen):
pika is not thread-safe.
"""

from dataclasses import asdict, dataclass
from datetime import datetime
import functools
import json
import threading
import logging
import pika
from typing import Optional
from common.qmsg_model import RpcRequest, RpcResponse
from common.qmsg_tools import QMessageTools


@dataclass
class RpcReceiverConfig:
    """
    Configuration dataclass for RpcServer.
    Holds the RabbitMQ connection details and operational parameters.
    """

    rabbitmq_host: str = "localhost"
    reconnect_time: int = 5
    force_name: str = ""
    force_ip: str = ""
    log_topic: str = "RpcServer"


class RpcReceiver:
    """
    The RpcServer class listens for and executes RPC requests sent by the server.
    It handles reconnection if the connection is lost.
    """

    def __init__(
        self,
        owner,
        config: RpcReceiverConfig,
    ) -> None:
        """
        Initialize the RpcServer with the provided RabbitMQ connection details.

        :param rabbitmq_host: The RabbitMQ host address.
        :param queue_name: The queue name for RPC requests.
        :param log_topic: The logging topic for RpcServer.
        """
        self.owner = owner
        self.config = config
        self.tools = QMessageTools()
        self.name = self.config.force_name
        if self.name == "":
            self.name = self.tools.get_own_name()
        self.ip_address = self.config.force_ip
        if self.ip_address == "":
            self.ip_address = self.tools.get_own_ip()

        self.logger = logging.getLogger(self.config.log_topic)
        # pika is not thread-safe: connection and channel belong to
        # thread_listen; other threads reach them only through
        # connection.add_callback_threadsafe
        self.connection: Optional[pika.BlockingConnection] = None
        self.channel: Optional[pika.channel.Channel] = None
        self.thread_listen: Optional[threading.Thread] = None
        self._stop_event = threading.Event()

    def connect(self) -> None:
        """
        Establish a connection to RabbitMQ. If the connection fails, retry after a delay.
        Runs in thread_listen.
        """
        while not self._stop_event.is_set():
            try:
                self.connection = pika.BlockingConnection(
                    pika.ConnectionParameters(host=self.config.rabbitmq_host)
                )
                self.channel = self.connection.channel()
                self.channel.queue_declare(queue=self.ip_address)
                # One request at a time: the next one is delivered after the
                # reply to the current one has been acked
                self.channel.basic_qos(prefetch_count=1)
                self.logger.info(
                    "RpcReceiver Connected to RabbitMQ at %s",
                    self.config.rabbitmq_host,
                )
                return
            except pika.exceptions.AMQPError as exe:
                self.logger.error(
                    "Connection failed, retrying in %s seconds... Error: %s",
                    self.config.reconnect_time,
                    exe,
                )
                self._stop_event.wait(self.config.reconnect_time)

    def on_request(self, channel, method, properties, body) -> None:
        """
        Called by pika in thread_listen. Executes the request in a worker thread,
        so that long running commands do not block pika's I/O (and its heartbeats).
        """
        connection = self.connection
        worker = threading.Thread(
            target=self.handle_request,
            args=[connection, channel, method, properties, body],
            daemon=True,
        )
        worker.start()

    def handle_request(self, connection, channel, method, properties, body) -> None:
        """
        Worker thread: execute the request, then hand the reply over to thread_listen.
        """
        request = None
        try:
            request = RpcRequest(**json.loads(body.decode()))
            response = self.owner.handle_request(request)
        except Exception as exe:
            self.logger.error("Failed to handle RpcRequest %s: %s", body, exe)
            response = RpcResponse(
                datetime.now().timestamp(),
                request,
                self.name,
                self.ip_address,
                {"code": -1, "std_out": "", "std_err": str(exe)},
            )
        reply = functools.partial(
            self.send_reply, channel, method, properties, response
        )
        try:
            connection.add_callback_threadsafe(reply)
        except Exception as exe:
            # Connection lost meanwhile: the unacked request is redelivered
            self.logger.error("Could not send reply, connection lost: %s", exe)

    def send_reply(self, channel, method, properties, response: RpcResponse) -> None:
        """
        Publish the response and ack the request. Runs in thread_listen.
        """
        if properties.reply_to:
            channel.basic_publish(
                exchange="",
                routing_key=properties.reply_to,
                properties=pika.BasicProperties(
                    correlation_id=properties.correlation_id,
                    content_type="application/json",
                ),
                body=json.dumps(asdict(response)),
            )
        channel.basic_ack(delivery_tag=method.delivery_tag)

    def run_in_thread(self) -> threading.Thread:
        """
        Run the RPC server in a separate thread.
        """
        self._stop_event.clear()
        self.thread_listen = threading.Thread(target=self.start_listening, daemon=True)
        self.thread_listen.start()
        self.logger.info("RpcServer thread started.")
        return self.thread_listen

    def start_listening(self) -> None:
        """
        Consume RPC requests until stop() is called; reconnect if the connection is lost.
        """
        self.logger.info(
            "RpcServer is now listening for requests (%s)", self.ip_address
        )
        while not self._stop_event.is_set():
            try:
                self.connect()
                if self.channel is not None and not self._stop_event.is_set():
                    self.channel.basic_consume(
                        queue=self.ip_address,
                        on_message_callback=self.on_request,
                        auto_ack=False,
                    )
                    self.logger.info("Consuming now")
                    self.channel.start_consuming()
            except Exception as exe:
                self.logger.error("Connection error while consuming. Error: %s", exe)
            self.close()
            if not self._stop_event.is_set():
                self._stop_event.wait(self.config.reconnect_time)
        self.logger.info("RpcServer thread stopped.")

    def close(self) -> None:
        """
        Close the connection. Runs in thread_listen.
        """
        try:
            if self.connection is not None and self.connection.is_open:
                self.connection.close()
        except Exception as exe:
            self.logger.info("Exception on close: %s", exe)
        self.connection = None
        self.channel = None

    def stop(self) -> None:
        """
        Stop the RpcServer and its associated thread.
        """
        self._stop_event.set()
        connection = self.connection
        channel = self.channel
        if connection is not None and channel is not None:
            try:
                connection.add_callback_threadsafe(channel.stop_consuming)
            except Exception as exe:
                self.logger.info("Exception on stop: %s", exe)
        if self.thread_listen is not None:
            self.thread_listen.join(timeout=10)
