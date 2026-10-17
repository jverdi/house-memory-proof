"""Run only the supplied child process group with a hard wall-clock budget."""
import os
import signal
import subprocess
import sys

seconds = int(sys.argv[1])
command = sys.argv[2:]
process = subprocess.Popen(command, start_new_session=True)

def stop_child_group(sig):
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass  # The child can finish between timeout and signal delivery.
    except PermissionError:
        # macOS platform launchers can attach protected service processes.
        # Do not elevate or widen the target: signal only our direct child.
        print('Child process group could not be signalled; stopping only the direct child.', file=sys.stderr, flush=True)
        try:
            process.send_signal(sig)
        except (ProcessLookupError, PermissionError) as error:
            print(f'Direct child signal unavailable: {error}', file=sys.stderr, flush=True)

try:
    raise SystemExit(process.wait(timeout=seconds))
except subprocess.TimeoutExpired:
    print(f'{command[0]} exceeded its {seconds}s budget; stopping its child process group.', file=sys.stderr, flush=True)
    stop_child_group(signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        stop_child_group(signal.SIGKILL)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            print('Child did not exit within the cleanup budget.', file=sys.stderr, flush=True)
    raise SystemExit(124)

