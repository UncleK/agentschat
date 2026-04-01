import argparse
import datetime as dt
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

MAIN_SESSION = "ses_2d28fff97ffe2yvUZ6mVMvD6lb"
TASK6_SESSION = "ses_2ca2d0ecaffebx4Z7JGmaNySvV"
PROJECT_DIR = r"E:\VP\agents chat"
DEFAULT_STALL_MINUTES = 30
MAX_RECENT_DESCENDANTS = 8
STOP_TIMEOUT_SECONDS = 120
RESUME_TIMEOUT_SECONDS = 240
POST_STOP_WAIT_SECONDS = 2
POST_RESUME_WAIT_SECONDS = 3

CONTINUE_PROMPT = "网络又断开了，继续所有任务"


def fmt_ms(ms: int | None):
    if not ms:
        return None
    return dt.datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M:%S")


def load_db_path() -> Path:
    return Path(os.environ["USERPROFILE"]) / ".local" / "share" / "opencode" / "opencode.db"


def get_session_info(cur, sid: str):
    row = cur.execute(
        "select id,parent_id,slug,directory,title,time_updated from session where id=?",
        [sid],
    ).fetchone()
    if not row:
        return None
    return {
        "id": row[0],
        "parent_id": row[1],
        "slug": row[2],
        "directory": row[3],
        "title": row[4],
        "time_updated": row[5],
        "time_updated_text": fmt_ms(row[5]),
    }


def get_latest_message(cur, sid: str):
    row = cur.execute(
        "select id,time_created,time_updated,data from message where session_id=? order by time_created desc limit 1",
        [sid],
    ).fetchone()
    if not row:
        return None
    data = json.loads(row[3])
    return {
        "id": row[0],
        "time_created": row[1],
        "time_updated": row[2],
        "time_created_text": fmt_ms(row[1]),
        "time_updated_text": fmt_ms(row[2]),
        "role": data.get("role"),
        "agent": data.get("agent"),
        "provider": data.get("providerID"),
        "model": data.get("modelID"),
        "finish": data.get("finish"),
        "error": data.get("error"),
    }


def get_descendant_sessions(cur, root_sid: str):
    rows = cur.execute(
        "select id,parent_id,slug,directory,title,time_updated from session order by time_updated desc"
    ).fetchall()
    by_parent = {}
    for row in rows:
        by_parent.setdefault(row[1], []).append(row)

    descendants = []
    queue = [root_sid]
    seen = set()
    while queue:
        parent = queue.pop(0)
        for row in by_parent.get(parent, []):
            sid = row[0]
            if sid in seen:
                continue
            seen.add(sid)
            info = {
                "id": row[0],
                "parent_id": row[1],
                "slug": row[2],
                "directory": row[3],
                "title": row[4],
                "time_updated": row[5],
                "time_updated_text": fmt_ms(row[5]),
            }
            descendants.append(info)
            queue.append(sid)

    descendants.sort(key=lambda x: x.get("time_updated") or 0, reverse=True)
    return descendants


def resolve_opencode_executable() -> str:
    local_appdata = Path(os.environ.get("LOCALAPPDATA", ""))
    appdata = Path(os.environ.get("APPDATA", ""))
    candidates = [
        local_appdata / "OpenCode" / "opencode-cli.exe",
        shutil.which("opencode-cli"),
        shutil.which("opencode-cli.exe"),
        shutil.which("opencode"),
        shutil.which("opencode.cmd"),
        appdata / "npm" / "opencode.cmd",
        appdata / "npm" / "opencode",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return str(candidate)
    raise FileNotFoundError("Unable to resolve opencode executable")


def tail_text(text, max_chars: int = 4000):
    if text is None:
        return ""
    if isinstance(text, bytes):
        text = text.decode("utf-8", errors="replace")
    return text[-max_chars:]


def run_opencode_command(cmd: list[str], timeout: int = 180) -> dict:
    started_at = dt.datetime.now()
    try:
        proc = subprocess.run(
            cmd,
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        finished_at = dt.datetime.now()
        return {
            "ok": proc.returncode == 0,
            "status": "ok" if proc.returncode == 0 else "returncode_nonzero",
            "command": cmd,
            "timeout_seconds": timeout,
            "started_at": started_at.strftime("%Y-%m-%d %H:%M:%S"),
            "finished_at": finished_at.strftime("%Y-%m-%d %H:%M:%S"),
            "duration_seconds": round((finished_at - started_at).total_seconds(), 1),
            "returncode": proc.returncode,
            "timed_out": False,
            "stdout": tail_text(proc.stdout),
            "stderr": tail_text(proc.stderr),
        }
    except subprocess.TimeoutExpired as exc:
        finished_at = dt.datetime.now()
        return {
            "ok": False,
            "status": "timeout",
            "command": cmd,
            "timeout_seconds": timeout,
            "started_at": started_at.strftime("%Y-%m-%d %H:%M:%S"),
            "finished_at": finished_at.strftime("%Y-%m-%d %H:%M:%S"),
            "duration_seconds": round((finished_at - started_at).total_seconds(), 1),
            "returncode": None,
            "timed_out": True,
            "error_type": type(exc).__name__,
            "error": str(exc),
            "stdout": tail_text(exc.stdout),
            "stderr": tail_text(exc.stderr),
        }
    except Exception as exc:
        finished_at = dt.datetime.now()
        return {
            "ok": False,
            "status": "exception",
            "command": cmd,
            "timeout_seconds": timeout,
            "started_at": started_at.strftime("%Y-%m-%d %H:%M:%S"),
            "finished_at": finished_at.strftime("%Y-%m-%d %H:%M:%S"),
            "duration_seconds": round((finished_at - started_at).total_seconds(), 1),
            "returncode": None,
            "timed_out": False,
            "error_type": type(exc).__name__,
            "error": str(exc),
            "stdout": "",
            "stderr": "",
        }


def stop_current_continuation() -> dict:
    opencode_exe = resolve_opencode_executable()
    cmd = [
        opencode_exe,
        "run",
        "--session",
        MAIN_SESSION,
        "--dir",
        PROJECT_DIR,
        "--command",
        "stop-continuation",
    ]
    return run_opencode_command(cmd, timeout=STOP_TIMEOUT_SECONDS)


def resume_main_session() -> dict:
    opencode_exe = resolve_opencode_executable()
    cmd = [
        opencode_exe,
        "run",
        "--session",
        MAIN_SESSION,
        "--dir",
        PROJECT_DIR,
        "--variant",
        "xhigh",
        CONTINUE_PROMPT,
    ]
    return run_opencode_command(cmd, timeout=RESUME_TIMEOUT_SECONDS)


def describe_message_error(msg: dict | None):
    if not msg:
        return None
    error = msg.get("error")
    if not error:
        return None
    if isinstance(error, dict):
        name = error.get("name")
        data = error.get("data") or {}
        message = data.get("message")
        if name and message:
            return f"{name}: {message}"
        if name:
            return name
    return str(error)


def compact_status_snapshot(status: dict):
    latest = status.get("latest_activity") or {}
    main_msg = status.get("main_latest_message") or {}
    task_msg = status.get("task6_latest_message") or {}
    return {
        "checked_at": status.get("checked_at"),
        "latest_activity": {
            "kind": latest.get("kind"),
            "id": latest.get("id"),
            "title": latest.get("title"),
            "time_updated_text": latest.get("time_updated_text"),
        },
        "latest_age_minutes": status.get("latest_age_minutes"),
        "stalled": status.get("stalled"),
        "main_latest_message": {
            "agent": main_msg.get("agent"),
            "model": main_msg.get("model"),
            "time_updated_text": main_msg.get("time_updated_text"),
            "finish": main_msg.get("finish"),
            "error": describe_message_error(main_msg),
        },
        "task6_latest_message": {
            "time_updated_text": task_msg.get("time_updated_text"),
            "finish": task_msg.get("finish"),
            "error": describe_message_error(task_msg),
        },
        "monitored_session_count": status.get("monitored_session_count"),
    }


def collect_status(stall_minutes: int) -> dict:
    db_path = load_db_path()
    if not db_path.exists():
        raise FileNotFoundError(f"db missing: {db_path}")

    with sqlite3.connect(str(db_path)) as conn:
        cur = conn.cursor()
        main_info = get_session_info(cur, MAIN_SESSION)
        task_info = get_session_info(cur, TASK6_SESSION)
        main_msg = get_latest_message(cur, MAIN_SESSION)
        task_msg = get_latest_message(cur, TASK6_SESSION)
        descendants = get_descendant_sessions(cur, MAIN_SESSION)

    now = dt.datetime.now()
    monitored = []
    if main_info:
        monitored.append(
            {
                "kind": "main",
                "id": main_info["id"],
                "title": main_info["title"],
                "time_updated": main_info["time_updated"],
                "time_updated_text": main_info["time_updated_text"],
            }
        )
    for info in descendants:
        monitored.append(
            {
                "kind": "descendant",
                "id": info["id"],
                "title": info["title"],
                "time_updated": info["time_updated"],
                "time_updated_text": info["time_updated_text"],
            }
        )

    monitored.sort(key=lambda x: x.get("time_updated") or 0, reverse=True)
    latest = monitored[0] if monitored else None
    latest_ms = latest.get("time_updated") if latest else None

    age_minutes = None
    stalled = None
    if latest_ms is not None:
        latest_dt = dt.datetime.fromtimestamp(latest_ms / 1000)
        age_minutes = round((now - latest_dt).total_seconds() / 60, 1)
        stalled = age_minutes >= stall_minutes

    health_issues = []
    main_error_text = describe_message_error(main_msg)
    if main_error_text:
        health_issues.append(f"main_message_error: {main_error_text}")
    task_error_text = describe_message_error(task_msg)
    if task_error_text:
        health_issues.append(f"task6_message_error: {task_error_text}")
    if stalled:
        health_issues.append("session_stalled")

    status = {
        "ok": True,
        "checked_at": now.strftime("%Y-%m-%d %H:%M:%S"),
        "project_dir": PROJECT_DIR,
        "stall_threshold_minutes": stall_minutes,
        "latest_activity": latest,
        "latest_age_minutes": age_minutes,
        "stalled": stalled,
        "main_session": main_info,
        "task6_session": task_info,
        "main_latest_message": main_msg,
        "task6_latest_message": task_msg,
        "recent_descendants": descendants[:MAX_RECENT_DESCENDANTS],
        "monitored_session_count": len(monitored),
        "health_issues": health_issues,
    }
    status["snapshot"] = compact_status_snapshot(status)
    return status


def classify_result(status_before: dict, resume_flow: dict | None):
    if not status_before.get("stalled"):
        return "healthy"
    if not resume_flow or not resume_flow.get("attempted"):
        return "stalled"

    final_status = resume_flow.get("final_status") or {}
    stop_attempt = resume_flow.get("stop_attempt") or {}
    resume_attempt = resume_flow.get("resume_attempt") or {}

    if not final_status.get("stalled"):
        if stop_attempt.get("status") == "timeout":
            return "recovered_after_stop_timeout"
        return "recovered"
    if resume_attempt.get("ok"):
        return "resume_sent_but_still_stalled"
    if stop_attempt.get("status") == "timeout":
        return "stop_timeout_and_resume_failed"
    return "resume_failed"


def build_summary(status_before: dict, resume_flow: dict | None, classification: str):
    latest_time = (status_before.get("latest_activity") or {}).get("time_updated_text")
    age = status_before.get("latest_age_minutes")
    if classification == "healthy":
        return f"OpenCode 正常推进中，最近活动时间 {latest_time}，距现在约 {age} 分钟。"
    if classification == "stalled":
        return f"OpenCode 当前已停滞，最近活动时间 {latest_time}，距现在约 {age} 分钟，尚未触发自动续跑。"
    if classification == "recovered":
        return "OpenCode 原先已停滞，但本轮 stop + resume 后已恢复到非 stalled 状态。"
    if classification == "recovered_after_stop_timeout":
        return "OpenCode 原先已停滞；stop-continuation 虽然超时，但恢复口令已补发，当前已回到非 stalled 状态。"
    if classification == "resume_sent_but_still_stalled":
        return "OpenCode 原先已停滞，本轮已补发恢复口令，但最新状态仍显示 stalled。"
    if classification == "stop_timeout_and_resume_failed":
        return "OpenCode 原先已停滞，stop-continuation 超时，且本轮恢复也未成功。"
    if classification == "resume_failed":
        return "OpenCode 原先已停滞，本轮恢复尝试未成功。"
    return "OpenCode 状态已检查完成。"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stall-minutes", type=int, default=DEFAULT_STALL_MINUTES)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    try:
        status_before = collect_status(args.stall_minutes)
        result = dict(status_before)
        result["resume_requested"] = bool(args.resume)
        result["resume_flow"] = None

        final_status = status_before
        resume_flow = None

        if args.resume:
            resume_flow = {
                "attempted": False,
                "decision": "skip_not_stalled",
            }
            if status_before.get("stalled"):
                resume_flow = {
                    "attempted": True,
                    "decision": "resume_after_best_effort_stop",
                }
                stop_attempt = stop_current_continuation()
                resume_flow["stop_attempt"] = stop_attempt

                time.sleep(POST_STOP_WAIT_SECONDS)
                status_after_stop = collect_status(args.stall_minutes)
                resume_flow["status_after_stop"] = compact_status_snapshot(status_after_stop)

                if not status_after_stop.get("stalled"):
                    resume_flow["decision"] = "skip_resume_recent_activity_after_stop"
                    final_status = status_after_stop
                else:
                    if stop_attempt.get("status") == "timeout":
                        resume_flow["decision"] = "resume_even_after_stop_timeout"
                    resume_attempt = resume_main_session()
                    resume_flow["resume_attempt"] = resume_attempt

                    time.sleep(POST_RESUME_WAIT_SECONDS)
                    status_after_resume = collect_status(args.stall_minutes)
                    resume_flow["status_after_resume"] = compact_status_snapshot(status_after_resume)
                    final_status = status_after_resume

            resume_flow["final_status"] = compact_status_snapshot(final_status)
            result["resume_flow"] = resume_flow

        classification = classify_result(status_before, resume_flow)
        result["classification"] = classification
        result["summary"] = build_summary(status_before, resume_flow, classification)
        result["final_status"] = compact_status_snapshot(final_status)
        result["final_stalled"] = final_status.get("stalled")

        print(json.dumps(result, ensure_ascii=False, indent=2))
    except FileNotFoundError as exc:
        print(
            json.dumps(
                {"ok": False, "error_type": type(exc).__name__, "error": str(exc)},
                ensure_ascii=False,
            )
        )
        sys.exit(2)
    except Exception as exc:
        print(
            json.dumps(
                {"ok": False, "error_type": type(exc).__name__, "error": str(exc)},
                ensure_ascii=False,
            )
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
