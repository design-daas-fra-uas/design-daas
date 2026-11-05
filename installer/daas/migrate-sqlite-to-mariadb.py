#!/usr/bin/env python3
"""
Copies the DaaS backend's data from its SQLite file into MariaDB (see
installer/daas/README.md). Run it once, with the backend stopped and the
MariaDB container running, from src/ with the backend's venv:

    cd src && sudo .venv/bin/python3 ../installer/daas/migrate-sqlite-to-mariadb.py

The schema comes from the backend's own models (ORMEntity.metadata), the
MariaDB settings from config/db.toml (+ config/local/db.toml for the
password). Refuses to copy into tables that already have rows. The SQLite
file is only read, never changed. Prints row counts, no data.
"""

import sys

from sqlalchemy import create_engine, func, insert, select

sys.path.insert(0, ".")
from app.daas.db.db_model import ORMEntity  # noqa: E402
from app.qweb.common.tomlfile import read_toml_with_local  # noqa: E402


def main() -> int:
    db = read_toml_with_local("config/db.toml")["db"]
    data = read_toml_with_local("config/qweb.toml")["sys"]["data_path"]
    sqlite_file = f"{data}/{db['data_path']}/sqlite/{db['db_name']}.sqlite3"
    if not db["db_pass"]:
        print("db_pass is empty: run make daas-configure first")
        return 1
    server = f"mysql+pymysql://{db['db_user']}:{db['db_pass']}@{db['db_host']}:{db['db_port']}"

    with create_engine(f"{server}/").connect() as con:
        con.exec_driver_sql(f"CREATE DATABASE IF NOT EXISTS `{db['db_name']}`")
    src = create_engine(f"sqlite:///{sqlite_file}")
    dst = create_engine(f"{server}/{db['db_name']}")
    ORMEntity.metadata.create_all(dst)
    print(f"From {sqlite_file} to MariaDB {db['db_host']}:{db['db_port']}/{db['db_name']}")

    failed = False
    with src.connect() as s, dst.begin() as d:
        for table in ORMEntity.metadata.sorted_tables:
            if d.execute(select(func.count()).select_from(table)).scalar():
                print(f"  {table.name}: MariaDB table is not empty, refusing to copy")
                return 1
            rows = [dict(r._mapping) for r in s.execute(select(table))]
            if rows:
                d.execute(insert(table), rows)
            copied = d.execute(select(func.count()).select_from(table)).scalar()
            ok = copied == len(rows)
            failed |= not ok
            print(f"  {table.name:28} sqlite {len(rows):4}  mariadb {copied:4}  {'ok' if ok else 'DIFFERENT'}")
        if failed:
            raise RuntimeError("row counts differ, nothing committed")
    print("All tables copied")
    return 0


if __name__ == "__main__":
    sys.exit(main())
