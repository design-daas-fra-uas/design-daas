#!/usr/bin/env python3
"""
Prints the `docker run` arguments for one service container, the same way
the DaaS backend starts it (src/config/container.toml [service_containers],
app/daas/container/docker/DockerRequest.py _create_run_config).

Usage: service_container.py <repo-folder> <container-name>

Output: one argument per line (image last), for
    mapfile -t args < <(service_container.py ...); docker run "${args[@]}"
Exit code 2 when the container is not in container.toml.
"""

import sys
import tomllib
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 1
    src = Path(sys.argv[1]) / "src"
    name = sys.argv[2]
    with open(src / "config" / "container.toml", "rb") as f:
        services = tomllib.load(f)["service_containers"]["service_containers"]
    with open(src / "config" / "qweb.toml", "rb") as f:
        data_path = src / tomllib.load(f)["sys"]["data_path"]

    for image, cname, opts, cpus, memory in services:
        if cname != name:
            continue
        args = [
            "-d", "--rm", "--name", cname,
            "--device", "/dev/rtc:/dev/rtc",
            "--cpuset-cpus", "0-7",
            "--cpu-period", "100000", "--cpu-quota", str(cpus * 100000),
            "--memory", f"{memory // 1024**2}m",
        ]
        for opt in opts:
            flag, _, value = opt.partition(" ")
            if flag == "--privileged":
                args.append("--privileged")
            elif flag == "-p":
                args += ["-p", value]
            elif flag == "-v":
                host, cnt, mode = value.split(":")
                # Relative paths are below src/data, like in the backend
                if not host.startswith("/"):
                    host = str(data_path / host)
                args += ["-v", f"{host}:{cnt}:{mode}"]
        args.append(image)
        print("\n".join(args))
        return 0
    print(f"{name} is not in {src / 'config' / 'container.toml'}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
