"""Info Tasks"""

from enum import Enum
from app.daas.common.enums import BackendName
from app.daas.common.model import Application, DaasObject
from app.daas.db.database import Database
from app.daas.objects.object_application import ApplicationObject
from app.daas.objects.object_container import ContainerObject
from app.daas.objects.object_machine import MachineObject
from app.daas.resources.info.monitoring import MonitoringInfo, MonitoringInfoTool
from app.daas.storage.filestore import Filestore
from app.qweb.common.common import TaskArgs
from app.qweb.common.enums import ScheduledTaskFilter
from app.qweb.common.qweb_tools import get_backend_component, get_database, get_service
from app.qweb.processing.processor import QwebResult
from app.daas.common.ctx import get_request_object_optional, log_task_arguments
from app.qweb.service.service_context import ServiceComponent
from app.qweb.service.service_tasks import QwebTaskManager


class AdminTask(Enum):
    """Info tasktype"""

    ADMIN_DASHBOARD = "ADMIN_DASHBOARD"
    ADMIN_MONITORING = "ADMIN_MONITORING"
    ADMIN_MONITORING_TASKS = "ADMIN_MONITORING_TASKS"
    ADMIN_MONITORING_APPS = "ADMIN_MONITORING_APPS"
    ADMIN_MONITORING_FILES = "ADMIN_MONITORING_FILES"
    ADMIN_MONITORING_SOCKETS = "ADMIN_MONITORING_SOCKETS"
    ADMIN_MONITORING_HOST = "ADMIN_MONITORING_HOST"
    ADMIN_MONITORING_OBJECTS = "ADMIN_MONITORING_OBEJCTS"
    ADMIN_MONITORING_UTILIZATION = "ADMIN_MONITORING_UTILIZATION"
    ADMIN_MONITORING_LIMITS = "ADMIN_MONITORING_LIMITS"
    ADMIN_ASSIGN_OBJ_TO_USER = "ADMIN_ASSIGN_OBJ_TO_USER"
    ADMIN_ASSIGN_APP = "ADMIN_ASSIGN_APP"
    ADMIN_TASK_LIST = "ADMIN_TASK_LIST"
    ADMIN_TASK_STOP = "ADMIN_TASK_STOP"
    ADMIN_DELETE_USER_DATA = "ADMIN_DELETE_USER_DATA"


async def admin_monitoring_info(args: TaskArgs) -> QwebResult:
    """Returns monitoring info object"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    userid = args.user.id_user
    mon = MonitoringInfoTool()
    detailed = False
    include_hostinfo = False
    taskinfo = await mon.create_monitoring_info_tasks(userid)
    fileinfo = await mon.create_monitoring_info_files(userid)
    appinfo = await mon.create_monitoring_info_apps(userid)
    socketinfo = await mon.create_monitoring_info_websockets(userid)
    hostinfo = await mon.create_monitoring_info_host(include_hostinfo)
    objinfo = await mon.create_monitoring_info_objects(detailed, userid)
    objutil = await mon.create_monitoring_info_utilization(userid)
    limitinfo = await mon.create_monitoring_info_limit(userid)
    info_all = MonitoringInfo(
        taskinfo, fileinfo, appinfo, hostinfo, socketinfo, objinfo, objutil, limitinfo
    )
    return QwebResult(200, info_all.tojson())


async def admin_monitoring_info_tasks(args: TaskArgs) -> QwebResult:
    """Returns monitoring info tasks"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    mon = MonitoringInfoTool()
    reqargs = args.req.request_context.request_args
    userid = _requested_owner(reqargs, args.user.id_user)
    taskinfo = await mon.create_monitoring_info_tasks(userid)
    return QwebResult(200, taskinfo.tojson())


async def admin_monitoring_info_apps(args: TaskArgs) -> QwebResult:
    """Returns app infos"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    mon = MonitoringInfoTool()
    reqargs = args.req.request_context.request_args
    userid = _requested_owner(reqargs, args.user.id_user)
    taskinfo = await mon.create_monitoring_info_apps(userid)
    return QwebResult(200, taskinfo.tojson())


async def admin_monitoring_info_files(args: TaskArgs) -> QwebResult:
    """Returns file infos"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    mon = MonitoringInfoTool()
    reqargs = args.req.request_context.request_args
    userid = _requested_owner(reqargs, args.user.id_user)
    taskinfo = await mon.create_monitoring_info_files(userid)
    return QwebResult(200, taskinfo.tojson())


async def admin_monitoring_info_sockets(args: TaskArgs) -> QwebResult:
    """Returns socket infos"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    mon = MonitoringInfoTool()
    reqargs = args.req.request_context.request_args
    userid = _requested_owner(reqargs, args.user.id_user)
    taskinfo = await mon.create_monitoring_info_websockets(userid)
    return QwebResult(200, taskinfo.tojson())


async def admin_monitoring_info_host(args: TaskArgs) -> QwebResult:
    """Returns host infos"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    include_hostinfo = True
    mon = MonitoringInfoTool()
    taskinfo = await mon.create_monitoring_info_host(include_hostinfo)
    return QwebResult(200, taskinfo.tojson())


async def admin_monitoring_info_objects(args: TaskArgs) -> QwebResult:
    """Returns object infos"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    mon = MonitoringInfoTool()
    reqargs = args.req.request_context.request_args
    userid = _requested_owner(reqargs, args.user.id_user)
    taskinfo = await mon.create_monitoring_info_objects(False, userid)
    return QwebResult(200, taskinfo.tojson())


async def admin_monitoring_info_utilization(args: TaskArgs) -> QwebResult:
    """Returns utilization infos"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    mon = MonitoringInfoTool()
    reqargs = args.req.request_context.request_args
    userid = _requested_owner(reqargs, args.user.id_user)
    taskinfo = await mon.create_monitoring_info_utilization(userid)
    return QwebResult(200, taskinfo.tojson())


async def admin_monitoring_info_limits(args: TaskArgs) -> QwebResult:
    """Returns resource limit infos"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    mon = MonitoringInfoTool()
    reqargs = args.req.request_context.request_args
    userid = _requested_owner(reqargs, args.user.id_user)
    taskinfo = await mon.create_monitoring_info_limit(userid)
    return QwebResult(200, taskinfo.tojson())


async def admin_assign_obj_to_user(args: TaskArgs) -> QwebResult:
    """Assigns obj to user"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    entity = get_request_object_optional(args.ctx, "entity", DaasObject)
    reqargs = args.req.request_context.request_args
    userid = int(reqargs["owner"])
    if entity is not None:
        if isinstance(entity, MachineObject | ContainerObject):
            changed = await entity.change_owner(userid)
            if changed:
                return QwebResult(200, {})
            return QwebResult(400, {}, 1, "Could not change ownership")
        return QwebResult(400, {}, 2, "Invalid object type")
    return QwebResult(400, {}, 3, "No object")


async def admin_assign_app(args: TaskArgs) -> QwebResult:
    """Assigns app to user"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    entity = get_request_object_optional(args.ctx, "entity", Application)
    reqargs = args.req.request_context.request_args
    userid = int(reqargs["owner"])
    if entity is not None:
        if isinstance(entity, ApplicationObject):
            changed = await entity.change_owner(userid)
            if changed:
                return QwebResult(200, {})
            return QwebResult(400, {}, 1, "Could not change ownership")
        return QwebResult(400, {}, 2, "Invalid app type")
    return QwebResult(400, {}, 3, "No app")


async def admin_tasklist(args: TaskArgs) -> QwebResult:
    """Returns task list"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    reqargs = args.req.request_context.request_args
    dicts = await _get_filtered_tasks(reqargs)
    return QwebResult(200, dicts)


async def admin_task_stop(args: TaskArgs) -> QwebResult:
    """Stops task"""
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    mancomp: QwebTaskManager = await get_service(ServiceComponent.TASK, QwebTaskManager)
    reqargs = args.req.request_context.request_args
    dicts = await _get_filtered_tasks(reqargs)
    for x in dicts:
        stopped = await mancomp.stop_scheduled_task(x["id_task"])
        if stopped is False:
            return QwebResult(400, {}, 1, "Error on stopping task")
    return QwebResult(200, {})


async def admin_delete_user_data(args: TaskArgs) -> QwebResult:
    """
    Removes everything a user owns, before their account is deleted in the
    auth backend: stops their tasks and running instances, then deletes their
    objects (VMs and containers, with their environments), files, apps and
    resource limit. Shared things (owner 0) are never touched.

    Keeps going when one item fails, so a single broken VM does not leave the
    rest behind, and answers 400 with every failure; the frontend then keeps
    the account so the admin can retry.
    """
    log_task_arguments(args.ctx, args.req, args.info, args.user)
    reqargs = args.req.request_context.request_args
    userid = _requested_owner(reqargs, 0)
    if userid <= 0:
        return QwebResult(400, {}, 1, "id_owner must be a user id above 0")

    dbase = await get_database(Database)
    failed: list[str] = []
    # Order matters: nothing may start again while objects are deleted
    deleted = {
        "tasks": await _stop_user_tasks(userid, failed),
        "instances": await _stop_user_instances(dbase, userid, failed),
        "objects": await _delete_user_objects(dbase, userid, failed),
        "files": await _delete_user_files(dbase, userid, failed),
        "apps": await _delete_user_apps(dbase, userid, failed),
    }
    if await dbase.get_limit(userid) is not None:
        if not await dbase.delete_limit(userid):
            failed.append("resource limit")

    if failed:
        msg = "Not deleted: " + ", ".join(failed)
        return QwebResult(400, {"deleted": deleted, "failed": failed}, 2, msg)
    return QwebResult(200, {"deleted": deleted, "failed": []})


async def _stop_user_tasks(userid: int, failed: list[str]) -> int:
    """Stops the user's running tasks; returns how many were stopped"""
    mancomp: QwebTaskManager = await get_service(ServiceComponent.TASK, QwebTaskManager)
    tasks = await mancomp.get_scheduled_tasks(ScheduledTaskFilter.RUNNING)
    count = 0
    for task in (await mancomp.filter_tasks(tasks, userid, "", "")).values():
        if await mancomp.stop_scheduled_task(task.id_task):
            count += 1
        else:
            failed.append(f"task {task.id_task}")
    return count


async def _stop_user_instances(dbase: Database, userid: int, failed: list[str]) -> int:
    """Stops the user's instances, also those started from shared objects"""
    count = 0
    for inst in await dbase.get_instances_by_owner(userid):
        app = getattr(inst, "app", None)
        obj = await dbase.get_daas_object(app.id if app is not None else inst.id_app)
        if isinstance(obj, MachineObject | ContainerObject):
            stopped = await obj.stop(inst, True)
        else:
            stopped = await dbase.delete_instance(inst)
        if stopped:
            count += 1
        else:
            failed.append(f"instance {inst.id}")
    return count


async def _delete_user_objects(dbase: Database, userid: int, failed: list[str]) -> int:
    """Deletes the user's objects with their environments (and the VM or image)"""
    count = 0
    for owned in await dbase.get_daas_objects_by_owner(userid):
        obj = await dbase.get_daas_object(owned.id)
        if not isinstance(obj, MachineObject | ContainerObject):
            failed.append(f"object {owned.id} (unknown type)")
            continue
        for env in await dbase.get_environments_by_object(obj.id):
            if not await obj.env_delete(env, {"id_owner": userid}):
                failed.append(f"environment {env.name} of object {obj.id}")
        if (await obj.baseimage_delete()).response_code == 200:
            count += 1
        else:
            failed.append(f"object {obj.id}")
    return count


async def _delete_user_files(dbase: Database, userid: int, failed: list[str]) -> int:
    """Deletes the user's uploaded files on disk and in the database"""
    filestore = await get_backend_component(BackendName.FILE, Filestore)
    count = 0
    for file in await dbase.get_user_files(userid):
        on_disk = await filestore.delete_user_file_upload(file.id, userid)
        in_db = await dbase.delete_file(file.id)
        if on_disk and in_db:
            count += 1
        else:
            failed.append(f"file {file.id}")
    return count


async def _delete_user_apps(dbase: Database, userid: int, failed: list[str]) -> int:
    """Deletes the user's own apps"""
    count = 0
    for app in await dbase.get_user_applications(userid):
        if await dbase.delete_application(app.id):
            count += 1
        else:
            failed.append(f"app {app.id}")
    return count


async def _get_filtered_tasks(reqargs: dict) -> list[dict]:

    userid = _requested_owner(reqargs, 0)
    objid = reqargs.get("id_object", "")
    instid = reqargs.get("id_instance", "")
    flt = ScheduledTaskFilter.ALL
    if "state" in reqargs:
        if reqargs["state"] == ScheduledTaskFilter.RUNNING.value:
            flt = ScheduledTaskFilter.RUNNING
        elif reqargs["state"] == ScheduledTaskFilter.FINAL.value:
            flt = ScheduledTaskFilter.FINAL
    mancomp: QwebTaskManager = await get_service(ServiceComponent.TASK, QwebTaskManager)
    tasks = await mancomp.get_scheduled_tasks(flt)
    filtered = await mancomp.filter_tasks(tasks, userid, objid, instid)
    return [v.to_json() for _, v in filtered.items()]


def _requested_owner(reqargs: dict, default: int) -> int:
    """
    The owner an admin request is about: id_owner as int, 0 (all users)
    when it is sent empty, default when it is not sent
    """
    if "id_owner" not in reqargs:
        return default
    owner = str(reqargs["id_owner"]).strip()
    return int(owner) if owner != "" else 0
