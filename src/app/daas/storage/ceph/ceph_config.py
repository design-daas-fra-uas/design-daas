from dataclasses import dataclass


@dataclass(kw_only=True)
class CephstoreFilesystemConfig:
    """Config data for Ceph filesystem"""

    enabled: bool
    name: str
    user: str
    folder_public: str
    folder_shared: str
    folder_user: str
    folder_keyrings: str
    folder_mount: str


@dataclass(kw_only=True)
class CephstoreConfig:
    """Config data for Ceph files"""

    enabled: bool
    daasfs: CephstoreFilesystemConfig
