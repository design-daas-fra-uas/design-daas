"""Info plugin"""

from app.qweb.service.service_plugin import LoadOrder, PluginBase
from app.daas.common.enums import ConfigFile, ConfigSections
from app.daas.resources.info.config import SysteminfoConfig
from app.plugins.resources.info.info_backend import InfoBackend
from app.plugins.resources.info.info_tasks import (
    InfoTask,
    dashboard_info,
    monitoring_info,
    monitoring_info_apps,
    monitoring_info_files,
    monitoring_info_host,
    monitoring_info_limits,
    monitoring_info_objects,
    monitoring_info_sockets,
    monitoring_info_tasks,
    monitoring_info_utilization,
    quota_info,
    system_status,
)
from app.plugins.resources.info.info_routes import handler


class InfoPlugin(PluginBase):
    """Info plugin"""

    def __init__(self):
        cfgfile_db = self.read_toml_file(ConfigFile.INFO)
        self.cfg = SysteminfoConfig(**cfgfile_db[ConfigSections.INFO_SYS.value])
        self.backend = InfoBackend(self.cfg)
        self.systasks = []
        self.apitasks = [
            (InfoTask.INFO_DASHBOARD.value, dashboard_info),
            (InfoTask.INFO_MONITORING.value, monitoring_info),
            (InfoTask.INFO_MONITORING_TASKS.value, monitoring_info_tasks),
            (InfoTask.INFO_MONITORING_APPS.value, monitoring_info_apps),
            (InfoTask.INFO_MONITORING_FILES.value, monitoring_info_files),
            (InfoTask.INFO_MONITORING_SOCKETS.value, monitoring_info_sockets),
            (InfoTask.INFO_MONITORING_HOST.value, monitoring_info_host),
            (InfoTask.INFO_MONITORING_OBJECTS.value, monitoring_info_objects),
            (InfoTask.INFO_MONITORING_UTILIZATION.value, monitoring_info_utilization),
            (InfoTask.INFO_MONITORING_LIMITS.value, monitoring_info_limits),
            (InfoTask.INFO_QUOTA.value, quota_info),
            (InfoTask.INFO_SYSTEM_STATUS.value, system_status),
        ]
        self.handlers = [handler]
        super().__init__(
            LoadOrder.Late,
            backends=[self.backend],
            handlers=self.handlers,
            systasks=self.systasks,
            apitasks=self.apitasks,
        )
