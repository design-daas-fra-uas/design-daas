"""
API documentation of the DaaS backend, generated from the route definitions.

Every route is declared as a BlueprintInfo in a *_routes.py module, with its
url, methods, arguments, access rules and a description. This module turns
those declarations into the API reference, so it can never drift from the
code:

- GET /api/docs       the reference as an HTML page (served by the backend)
- GET /api/docs.json  the same data as JSON
- `make api-docs` in src/ writes it to docs/api.md (scripts/api_docs.py)

The test routes (app/plugins/testing, only loaded with
qweb.toml enable_testing) are left out.
"""

import html
import importlib
from dataclasses import dataclass

from app.qweb.blueprints.blueprint_info import AuthenticationMode, BlueprintInfo

# Modules with an `infos` list of BlueprintInfo, in the order of the reference
ROUTE_MODULES = [
    "app.qweb.blueprints.blueprint_defaults",
    "app.plugins.core.auth.auth_routes",
    "app.plugins.core.task.task_routes",
    "app.plugins.platform.vm.vm_routes",
    "app.plugins.platform.container.container_routes",
    "app.plugins.platform.instances.inst_routes",
    "app.plugins.platform.phases.phases_routes",
    "app.plugins.platform.proxy.proxy_routes",
    "app.plugins.platform.extensions.extensions_routes",
    "app.plugins.platform.node.node_routes",
    "app.plugins.resources.admin.admin_routes",
    "app.plugins.resources.info.info_routes",
    "app.plugins.resources.limits.limits_routes",
    "app.plugins.storage.files.file_routes",
]


@dataclass
class RouteDoc:
    """One route of the reference"""

    group: str
    url: str
    methods: list[str]
    name: str
    description: str
    access: str
    mandatory: list[str]
    optional: list[str]
    files: list[str]
    query: list[str]
    content_type: str
    websocket: bool


def collect_route_docs() -> list[RouteDoc]:
    """The documentation of every route, grouped by module"""
    result = []
    for module_name in ROUTE_MODULES:
        module = importlib.import_module(module_name)
        group = module_name.rsplit(".", 1)[-1].replace("_routes", "")
        group = "default" if group == "blueprint_defaults" else group
        for info in module.infos:
            result.append(_route_doc(group, info))
    return result


def _route_doc(group: str, info: BlueprintInfo) -> RouteDoc:
    return RouteDoc(
        group=group,
        url=info.url,
        methods=list(info.methods),
        name=info.name,
        description=info.description or "-",
        access=_access(info),
        mandatory=list(info.request_args_mandatory),
        optional=list(info.request_args_optional),
        files=list(info.request_args_file),
        query=list(info.request_args_query),
        content_type=info.content_type,
        websocket=info.websocket_request,
    )


def _access(info: BlueprintInfo) -> str:
    if info.auth_params == AuthenticationMode.NONE:
        return "public"
    if info.admin_only:
        return "admin"
    if info.protect_system_objects:
        return "login (system objects: admin)"
    return "login"


def render_markdown(docs: list[RouteDoc]) -> str:
    """The reference as Markdown (docs/api.md)"""
    lines = [
        "# DaaS backend API",
        "",
        "Generated from the route definitions (`src/app/plugins/**/*_routes.py`) by",
        "`make api-docs` in `src/`; do not edit by hand. The running backend serves",
        "the same reference at `/api/docs` (HTML) and `/api/docs.json`.",
        "",
        "Requests send their arguments as form fields (multipart) or JSON; every",
        "route except the public ones needs `Authorization: Bearer <token>` from the",
        "auth service. `X-Request-ID` is optional and is written into the logs.",
        "",
    ]
    group = None
    for doc in docs:
        if doc.group != group:
            group = doc.group
            lines += [f"## {group}", ""]
        kind = "WEBSOCKET" if doc.websocket else " ".join(doc.methods)
        lines += [f"### `{kind} {doc.url}`", "", doc.description, ""]
        lines.append(f"- Access: {doc.access}")
        for label, values in (
            ("Required", doc.mandatory),
            ("Optional", doc.optional),
            ("Files", doc.files),
            ("Query", doc.query),
        ):
            if values:
                lines.append(f"- {label}: " + ", ".join(f"`{v}`" for v in values))
        lines.append(f"- Response: `{doc.content_type}`")
        lines.append("")
    return "\n".join(lines)


def render_html(docs: list[RouteDoc]) -> str:
    """The reference as a small standalone HTML page"""
    rows = []
    for doc in docs:
        args = []
        for label, values in (
            ("required", doc.mandatory),
            ("optional", doc.optional),
            ("files", doc.files),
            ("query", doc.query),
        ):
            if values:
                args.append(f"<b>{label}</b>: {html.escape(', '.join(values))}")
        kind = "WS" if doc.websocket else " ".join(doc.methods)
        rows.append(
            "<tr>"
            f"<td>{html.escape(doc.group)}</td>"
            f"<td><code>{html.escape(kind)}</code></td>"
            f"<td><code>{html.escape(doc.url)}</code></td>"
            f"<td>{html.escape(doc.description)}</td>"
            f"<td>{html.escape(doc.access)}</td>"
            f"<td>{'<br>'.join(args)}</td>"
            "</tr>"
        )
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>DaaS backend API</title><style>"
        "body{font-family:sans-serif;margin:2rem}table{border-collapse:collapse}"
        "td,th{border:1px solid #ccc;padding:4px 8px;vertical-align:top;text-align:left}"
        "th{background:#eee}</style></head><body>"
        f"<h1>DaaS backend API</h1><p>{len(docs)} routes, generated from the route "
        "definitions. JSON: <a href='/api/docs.json'>/api/docs.json</a></p>"
        "<table><tr><th>Group</th><th>Method</th><th>URL</th><th>Description</th>"
        "<th>Access</th><th>Arguments</th></tr>"
        + "".join(rows)
        + "</table></body></html>"
    )


def install_api_docs(app) -> None:
    """Registers GET /api/docs and /api/docs.json on a Quart app"""
    from dataclasses import asdict

    async def docs_html():
        return render_html(collect_route_docs()), 200, {"Content-Type": "text/html"}

    async def docs_json():
        return {"routes": [asdict(doc) for doc in collect_route_docs()]}

    app.add_url_rule("/api/docs", "api_docs", docs_html, methods=["GET"])
    app.add_url_rule("/api/docs.json", "api_docs_json", docs_json, methods=["GET"])
