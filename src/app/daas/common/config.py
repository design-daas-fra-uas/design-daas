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
class InstanceControllerConfig:
    """
    Config object for InstanceController. The SSH settings for instances
    are in [inst_ssh] (SshAdapterConfig).
    """

    enable_message_queue: bool
    test_method_online_state: str
