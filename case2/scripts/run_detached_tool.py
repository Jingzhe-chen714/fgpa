"""Run one Windows tool outside the caller's Job Object, with persistent logs.

Launch xvlog, xelab, and xsim separately.  The detached worker verifies that it
is outside a Job Object before starting the tool; a failed breakaway is fatal.
Only JSON status/log artifacts are written.  Existing paths are not reused.
"""

import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone


def in_job():
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    kernel.IsProcessInJob.argtypes = [wintypes.HANDLE, wintypes.HANDLE,
                                     ctypes.POINTER(wintypes.BOOL)]
    kernel.IsProcessInJob.restype = wintypes.BOOL
    result = wintypes.BOOL()
    if not kernel.IsProcessInJob(kernel.GetCurrentProcess(), None,
                                 ctypes.byref(result)):
        raise ctypes.WinError(ctypes.get_last_error())
    return bool(result.value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("This launcher requires Windows.")
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("A command is required after --.")
    work_dir = Path(args.cwd).resolve(strict=True)
    log_path = Path(args.log).resolve()
    status_path = Path(args.status).resolve()
    if log_path == status_path:
        parser.error("Log and status paths must differ.")

    if not args.worker:
        for path in (log_path, status_path):
            if path.exists():
                parser.error(f"Refusing to overwrite {path}")
            if not path.parent.is_dir():
                parser.error(f"Missing output directory: {path.parent}")
        worker_command = [sys.executable, str(Path(__file__).resolve()),
                          "--worker", "--cwd", str(work_dir),
                          "--log", str(log_path), "--status", str(status_path),
                          "--", *command]
        flags = (subprocess.DETACHED_PROCESS |
                 subprocess.CREATE_NEW_PROCESS_GROUP |
                 subprocess.CREATE_BREAKAWAY_FROM_JOB)
        worker = subprocess.Popen(worker_command, cwd=work_dir,
                                  stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL,
                                  close_fds=True, creationflags=flags)
        print(json.dumps({"worker_pid": worker.pid,
                          "log": str(log_path), "status": str(status_path)}))
        return 0

    status = {"worker_pid": os.getpid(), "command": command,
              "started": datetime.now(timezone.utc).isoformat()}

    def save_status():
        status_path.write_text(json.dumps(status, indent=2), encoding="utf-8")

    try:
        status["worker_in_job"] = in_job()
        if status["worker_in_job"]:
            raise RuntimeError("Worker is still in a Job Object; tool not started.")
        status["state"] = "running"
        save_status()
        tool_command = command
        if Path(command[0]).suffix.lower() in (".bat", ".cmd"):
            comspec = os.environ.get("COMSPEC", r"C:\Windows\System32\cmd.exe")
            tool_command = (f'"{comspec}" /d /s /c "'
                            f'{subprocess.list2cmdline(command)}"')
        with log_path.open("xb") as log_file:
            tool = subprocess.Popen(tool_command, cwd=work_dir,
                                    stdin=subprocess.DEVNULL, stdout=log_file,
                                    stderr=subprocess.STDOUT, close_fds=True,
                                    creationflags=subprocess.CREATE_NO_WINDOW)
            status["tool_pid"] = tool.pid
            save_status()
            status["returncode"] = tool.wait()
        status["state"] = "completed"
    except Exception as exc:
        status["state"] = "failed"
        status["error"] = str(exc)
        status["returncode"] = 1
    status["finished"] = datetime.now(timezone.utc).isoformat()
    save_status()
    return status["returncode"]


if __name__ == "__main__":
    sys.exit(main())
