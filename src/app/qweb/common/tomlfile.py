"""Reads config toml files with their local override"""

import os
import tomllib
from typing import Any

# Next to the config files: config/local/<name>.toml. Holds values that must
# not be in git (passwords); written by the installer
# (installer/daas/configure.bash), ignored by git.
LOCAL_FOLDER = "local"


def read_toml_with_local(fullname: str) -> dict[str, Any]:
    """
    Reads fullname and merges config/local/<same name> over it, key by key
    (tables are merged, other values replaced). Returns {} when fullname
    does not exist.
    """
    if not os.path.exists(fullname):
        return {}
    with open(file=fullname, mode="rb") as pointer:
        data = tomllib.load(pointer)
    local = os.path.join(
        os.path.dirname(fullname), LOCAL_FOLDER, os.path.basename(fullname)
    )
    if os.path.exists(local):
        with open(file=local, mode="rb") as pointer:
            _merge(data, tomllib.load(pointer))
    return data


def _merge(base: dict[str, Any], override: dict[str, Any]):
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            _merge(base[key], value)
        else:
            base[key] = value
