import json
import os
import pty
import random
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

TRUST_PROMPT = re.compile(rb"trust", re.IGNORECASE)
ESCAPE = b"\x1b"
ARROW_DOWN = b"\x1b[B"


def require_opt_in():
    if os.environ.get("SMITH_LIVE_CONTEXT_RESET_EVAL") != "1":
        print("SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run this live probe")
        sys.exit(0)
    if shutil.which("claude") is None:
        print("SKIP: claude is not on PATH")
        sys.exit(0)


def is_alive(pid):
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def read_pid(path):
    try:
        with open(path) as handle:
            return int(handle.read().strip() or 0)
    except (FileNotFoundError, ValueError):
        return 0


def child_still_running(pid):
    try:
        reaped, _ = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return False
    return reaped == 0


def read_job_state(work):
    try:
        with open(os.path.join(work, "job.dir")) as handle:
            job_dir = handle.read().strip()
        with open(os.path.join(job_dir, "state")) as handle:
            return handle.readline().strip()
    except FileNotFoundError:
        return None


def drain(fd, seconds):
    collected = b""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            collected += chunk
    return collected


def write_runner(work, hold_seconds):
    runner = os.path.join(work, "runner.sh")
    log = os.path.join(work, "signals.log")
    with open(runner, "w") as handle:
        handle.write(
            "#!/bin/bash\n"
            "for signal in INT TERM HUP QUIT; do\n"
            f"  trap \"echo $signal >> '{log}'; kill \\$(jobs -p) 2> /dev/null; exit 1\" \"$signal\"\n"
            "done\n"
            f"echo $$ > '{work}/runner.pid'\n"
            f"sleep {hold_seconds} &\n"
            f"echo $! > '{work}/child.pid'\n"
            "wait\n"
            f"echo wait-returned >> '{log}'\n"
        )
    os.chmod(runner, 0o755)
    return log


def write_worker_runner(work, hold_seconds, model):
    runner = os.path.join(work, "runner.sh")
    log = os.path.join(work, "signals.log")
    lib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib", "isolated-worker.sh")
    with open(os.path.join(work, "hold.sh"), "w") as handle:
        handle.write(f"#!/bin/bash\necho $$ >> '{work}/tools.pids'\nexec sleep {hold_seconds}\n")
    os.chmod(os.path.join(work, "hold.sh"), 0o755)
    prompt = "Run exactly ./hold.sh with the Bash tool in the foreground, with timeout 600000, then reply done."
    with open(runner, "w") as handle:
        handle.write(
            "#!/bin/bash\n"
            f"cd '{work}' || exit 70\n"
            f". '{lib}'\n"
            "for signal in INT TERM HUP QUIT; do\n"
            f"  trap \"echo $signal >> '{log}'; kill \\$(jobs -p) 2> /dev/null; exit 1\" \"$signal\"\n"
            "done\n"
            f"echo $$ > '{work}/runner.pid'\n"
            "for name in first second; do\n"
            f"  build_isolated_worker_argv {model} 'Bash(./hold.sh)' 'Glob Grep' json '{prompt}' --setting-sources '' --tools Bash\n"
            f"  \"${{ISOLATED_WORKER_ARGV[@]}}\" > '{work}/'$name.json 2>&1 &\n"
            f"  echo $! >> '{work}/workers.pids'\n"
            "done\n"
            "wait\n"
            f"echo wait-returned >> '{log}'\n"
        )
    os.chmod(runner, 0o755)
    return log


def sleepers(work):
    try:
        with open(os.path.join(work, "tools.pids")) as handle:
            recorded = [int(line) for line in handle if line.strip()]
    except FileNotFoundError:
        return []
    return [pid for pid in recorded if is_alive(pid)]


WORKER_JOB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "worker-job.sh")


def write_job_wrappers(work):
    with open(os.path.join(work, "start.sh"), "w") as handle:
        handle.write(f"#!/bin/bash\n'{WORKER_JOB}' start --deadline 900 -- '{work}/runner.sh' > '{work}/job.dir'\necho started\n")
    with open(os.path.join(work, "join.sh"), "w") as handle:
        handle.write(f"#!/bin/bash\necho $$ > '{work}/join.pid'\nexec '{WORKER_JOB}' join \"$(cat '{work}/job.dir')\" --max 540\n")
    os.chmod(os.path.join(work, "start.sh"), 0o755)
    os.chmod(os.path.join(work, "join.sh"), 0o755)


def run(model, with_workers, through_job=False):
    work = tempfile.mkdtemp(prefix="foreground-escape.")
    hold_seconds = random.randint(300, 800)
    if with_workers:
        log = write_worker_runner(work, hold_seconds, model)
    else:
        log = write_runner(work, hold_seconds)
    if through_job:
        write_job_wrappers(work)
    environment = {key: value for key, value in os.environ.items() if key != "CLAUDE_JOB_DIR"}
    environment["CTX_AUTO_RESET_DISPATCH"] = "0"
    command = [
        "claude", "--setting-sources", "", "--strict-mcp-config",
        "--model", model, "--tools", "Bash",
        "--allowedTools", "Bash(./start.sh) Bash(./join.sh)" if through_job else "Bash(./runner.sh)",
    ]
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(work)
        os.execvpe("claude", command, environment)
    screen = drain(fd, 8)
    trust_prompt_seen = bool(TRUST_PROMPT.search(screen))
    if trust_prompt_seen:
        os.write(fd, ARROW_DOWN)
        drain(fd, 1)
        os.write(fd, b"\r")
        drain(fd, 6)
    if through_job:
        os.write(fd, b"Use the Bash tool to run exactly ./start.sh, then use the Bash tool again to run exactly ./join.sh in the foreground with timeout 600000, then reply done.")
    else:
        os.write(fd, b"Run exactly ./runner.sh with the Bash tool in the foreground, with timeout 600000, then reply done.")
    drain(fd, 1)
    os.write(fd, b"\r")
    def ready():
        if through_job and not is_alive(read_pid(os.path.join(work, "join.pid"))):
            return False
        if with_workers:
            return len(sleepers(work)) >= 2
        return is_alive(read_pid(os.path.join(work, "child.pid")))
    waited = 0
    while not ready() and waited < 150:
        drain(fd, 1)
        waited += 1
    runner_pid = read_pid(os.path.join(work, "runner.pid"))
    if with_workers:
        try:
            with open(os.path.join(work, "workers.pids")) as handle:
                children = [int(line) for line in handle if line.strip()]
        except FileNotFoundError:
            children = []
        tool_processes = sleepers(work)
    else:
        children = [read_pid(os.path.join(work, "child.pid"))]
        tool_processes = []
    started = ready()
    os.write(fd, ESCAPE)
    drain(fd, 10)
    runner_alive = is_alive(runner_pid)
    children_alive = [child for child in children if is_alive(child)]
    tools_alive = [tool for tool in tool_processes if is_alive(tool)]
    session_alive = child_still_running(pid)
    job_state = None
    if through_job:
        polled = 0
        job_state = read_job_state(work)
        while job_state in (None, "RUNNING") and polled < 25:
            drain(fd, 1)
            polled += 1
            job_state = read_job_state(work)
    for target in [runner_pid] + children_alive + tools_alive:
        if is_alive(target):
            os.kill(target, signal.SIGTERM)
    if child_still_running(pid):
        os.kill(pid, signal.SIGTERM)
        drain(fd, 2)
        child_still_running(pid)
    try:
        with open(log) as handle:
            trapped = [line.strip() for line in handle if line.strip()]
    except FileNotFoundError:
        trapped = []
    return {
        "variant": "worker-job-join-of-runner-with-isolated-claude-workers" if through_job else ("runner-starts-isolated-claude-workers" if with_workers else "runner-starts-sleep"),
        "jobState": job_state,
        "trustPromptAnswered": trust_prompt_seen,
        "secondsUntilRunnerStarted": waited,
        "runnerStarted": started,
        "signalsTheRunnerTrapped": trapped,
        "runnerChildrenBefore": len(children),
        "workerToolProcessesBefore": len(tool_processes),
        "runnerAliveAfter": runner_alive,
        "runnerChildrenAliveAfter": len(children_alive),
        "workerToolProcessesAliveAfter": len(tools_alive),
        "interactiveSessionAliveAfter": session_alive,
        "pass": started and not runner_alive and not children_alive and not tools_alive
        and (not through_job or job_state == "SMITH_JOB_CANCELLED"),
    }


def main():
    require_opt_in()
    out = sys.argv[1]
    model = os.environ.get("SMITH_LIVE_CONTEXT_RESET_MODEL", "haiku")
    version = subprocess.run(["claude", "--version"], capture_output=True, text=True).stdout.strip()
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude"))
    selected = os.environ.get("SMITH_LIVE_ESCAPE_VARIANTS", "sleep,workers,job").split(",")
    variants = []
    if "sleep" in selected:
        variants.append(run(model, False))
    if "workers" in selected:
        variants.append(run(model, True))
    if "job" in selected:
        variants.append(run(model, True, through_job=True))
    record = {
        "recordedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "claudeCodeVersion": version,
        "profile": config_dir.replace(os.path.expanduser("~"), "~", 1),
        "model": model,
        "setup": "interactive claude in a pseudo-terminal runs ./runner.sh in its foreground Bash tool, then the Escape key byte is written to the terminal; runner traps INT TERM HUP QUIT, logs the signal and kills its background jobs, which are a sleep in one variant and both isolated claude -p workers, each holding a sleep in its own Bash tool, in the other; a third variant starts the runner with worker-job.sh start and presses Escape during worker-job.sh join",
        "variants": variants,
        "passingVariants": [variant["variant"] for variant in variants if variant["pass"]],
    }
    record["recordedAt"] = record["recordedAt"][:-2] + ":" + record["recordedAt"][-2:]
    with open(out, "w") as handle:
        json.dump(record, handle, indent=2)
        handle.write("\n")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
