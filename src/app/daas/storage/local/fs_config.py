from dataclasses import dataclass


@dataclass(kw_only=True)
class FilestoreConfig:
    """Config data for Filestore"""

    folder_upload: str
    """Folder for user uploads"""

    folder_shared: str
    """Folder for shared user uploads"""

    folder_tmp: str
    """Global temp folder"""

    folder_docker: str
    """Global dockerfile folder"""

    folder_endpoint_info: str
    """Global dockerfile folder"""

    folder_inst_status: str
    """Instance status folder"""

    instance_status_outfile_name: str
    """The filename where output is stored"""
