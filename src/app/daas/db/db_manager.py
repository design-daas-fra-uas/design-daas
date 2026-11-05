"""Database manager"""

import os
import time
from typing import Optional
from sqlalchemy.schema import MetaData
from sqlalchemy import Engine, create_engine
from app.daas.common.config import DatabaseConfig
from app.daas.db.db_api import DatabaseApi
from app.daas.db.db_model import ORMEntity
from app.qweb.logging.logging import LogTarget, Loggable


# Connection attempts to MariaDB at startup (MARIADB_CONNECT_TRIES x WAIT_S)
MARIADB_CONNECT_TRIES = 30
MARIADB_CONNECT_WAIT_S = 2


class DatabaseManager(Loggable):
    """Manages connections to the database"""

    def __init__(self, config: DatabaseConfig):
        Loggable.__init__(self, LogTarget.DB)
        self.cfg = config
        self.connected = False

    def initialize(self):
        self.engine = self.__create_engine()
        if self.engine is not None:
            self.metadata = ORMEntity.metadata
            self.metadata.create_all(self.engine)
            self.api = self._create_api(self.engine, self.metadata)
        else:
            raise ValueError("DB-Engine is None")

    def __create_engine(self) -> Optional[Engine]:
        if self.cfg.db_type == "mariadb":
            return self.__create_engine_mariadb()
        if self.cfg.db_type == "sqlite":
            return self.__create_engine_sqlite()
        return None

    def __create_engine_mariadb(self):
        self._log_info(
            f"Prepare engine: mariadb ({self.cfg.db_host}:{self.cfg.db_port})"
        )
        constring = self.__create_connection_string_mariadb(False)
        engine = create_engine(constring, echo=self.cfg.enable_echo)
        # The backend starts the MariaDB container itself just before this
        # (ContainerPlugin), so give the server time to accept connections
        for attempt in range(1, MARIADB_CONNECT_TRIES + 1):
            try:
                self.api = self._create_api(engine, ORMEntity.metadata)
                self.api.connect()
                self.api.db_session_create(self.cfg.db_name)
                self.api.disconnect()
                constring = self.__create_connection_string_mariadb()
                return create_engine(constring, echo=self.cfg.enable_echo)
            except Exception as exe:
                if attempt == MARIADB_CONNECT_TRIES:
                    raise Exception(f"Error on db connect: {exe}")
                self._log_info(
                    f"MariaDB not ready ({attempt}/{MARIADB_CONNECT_TRIES}), "
                    f"retrying in {MARIADB_CONNECT_WAIT_S}s"
                )
                time.sleep(MARIADB_CONNECT_WAIT_S)
        return None

    def __create_engine_sqlite(self):
        try:
            self._log_info(f"Prepare engine: sqlite ({self.cfg.db_name}.sqlite)")
            constring = self.__create_connection_string_sqlite()
            return create_engine(constring, echo=self.cfg.enable_echo)
        except Exception as exe:
            raise Exception(f"Error on db connect: {exe}")

    def __create_connection_string_mariadb(self, with_db: bool = True):
        dbtype = self.cfg.db_type
        datapath = f"{self.cfg.data_path}/{dbtype}"
        os.makedirs(datapath, exist_ok=True)
        dbname = self.cfg.db_name
        user = self.cfg.db_user
        password = self.cfg.db_pass
        host = self.cfg.db_host
        port = self.cfg.db_port
        if with_db is True:
            return f"mysql+pymysql://{user}:{password}@{host}:{port}/{dbname}"
        return f"mysql+pymysql://{user}:{password}@{host}:{port}/"

    def __create_connection_string_sqlite(self):
        dbtype = self.cfg.db_type
        datapath = f"{self.cfg.data_path}/{dbtype}"
        os.makedirs(datapath, exist_ok=True)
        dbname = f"{self.cfg.db_name}.sqlite3"
        full = f"{datapath}/{dbname}"
        constring = f"sqlite:///{full}"
        return constring

    def _create_api(self, engine: Engine, metadata: MetaData):
        return DatabaseApi(engine, metadata)

    async def connect(self) -> bool:
        """Connects all databases"""
        if self.connected is False:
            self.initialize()
            self.api.connect()
            self.connected = True
            return self.connected
        return False

    async def disconnect(self) -> bool:
        """Disconnect all databases"""
        if self.connected is True:
            self.api.disconnect()
            self.connected = False
            return True
        return False

