from dataclasses import dataclass


@dataclass(kw_only=True)
class DatabaseConfig:
    """Config for databases"""

    data_path: str
    db_name: str
    db_user: str
    db_pass: str
    db_host: str
    db_port: int
    db_type: str

    enable_echo: bool = False

    include_samples: bool


@dataclass
# pylint: disable=too-many-instance-attributes
class InstanceControllerConfig:
    """
    Config object for InstanceController
    """

    sshuser: str
    sshport: int
    sshopt_timeout: int
    sshopt_strictcheck: str
    sshopt_nohostauth: str
    prefixip: str
    logcmd: bool
    logresult: bool
    enable_message_queue: bool
    test_method_online_state: str
