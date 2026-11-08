"""
Writes the API reference of the DaaS backend to docs/api.md (in the
repository root), generated from the route definitions. Run from src/:

    make api-docs
"""

import os
import sys

SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, SRC)

# pylint: disable=wrong-import-position
from app.qweb.blueprints.api_docs import (
    collect_route_docs,
    render_markdown,
)  # noqa: E402

TARGET = os.path.join(SRC, "..", "docs", "api.md")


def main() -> None:
    """Writes docs/api.md"""
    docs = collect_route_docs()
    os.makedirs(os.path.dirname(TARGET), exist_ok=True)
    with open(TARGET, "w", encoding="utf-8") as pointer:
        pointer.write(render_markdown(docs))
    print(f"Wrote {os.path.normpath(TARGET)} ({len(docs)} routes)")


if __name__ == "__main__":
    main()
