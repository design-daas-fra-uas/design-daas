"""
One id per request, shared by the whole stack (frontend -> DaaS backend ->
auth service).

The frontend sends an X-Request-ID header with every call. The backend keeps
that id (or creates one) for the request, writes it into every log line of
the request ([%(request_id)s] in logging.toml log_prefix), returns it in the
response and passes it on to the auth service (adapter_http), so one user
action can be followed through the logs of all three services.

The id lives in a context variable: tasks started from a request
(asyncio.create_task copies the context) log with the same id.
"""

import contextvars
import logging
import re
import uuid

HEADER = "X-Request-ID"
# Shown for log lines outside a request (startup, timers)
NO_REQUEST = "-"

_REQUEST_ID: contextvars.ContextVar[str] = contextvars.ContextVar(
    "request_id", default=NO_REQUEST
)
# Short, and only characters that are safe in a log line
_VALID_ID = re.compile(r"[A-Za-z0-9._-]{1,64}")


def resolve_request_id(header: str | None) -> str:
    """Returns header if it is a valid id, otherwise a new one"""
    if header is not None and _VALID_ID.fullmatch(header):
        return header
    return str(uuid.uuid4())


def set_request_id(request_id: str) -> None:
    """Sets the id of the current request (and of tasks started from it)"""
    _REQUEST_ID.set(request_id)


def get_request_id() -> str:
    """Id of the current request, NO_REQUEST outside of one"""
    return _REQUEST_ID.get()


class RequestIdLogFilter(logging.Filter):
    """Adds record.request_id for the %(request_id)s placeholder"""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = get_request_id()
        return True


def install_request_id(app) -> None:
    """Registers the request id hooks on a Quart app"""

    @app.before_request
    async def _before_request():
        from quart import request

        set_request_id(resolve_request_id(request.headers.get(HEADER)))

    @app.before_websocket
    async def _before_websocket():
        from quart import websocket

        set_request_id(resolve_request_id(websocket.headers.get(HEADER)))

    @app.after_request
    async def _after_request(response):
        response.headers[HEADER] = get_request_id()
        return response
