"""Run checkout UI across two real force-stops on a dedicated emulator.

Usage: python3 integration_test/support/checkout_process_recovery.py emulator-5556
Only checkout-process-recovery.db is reset; app data/Keystore are never cleared.
The test intentionally loses its VM twice. A final fresh-process test verifies
one bill/payment and one unit of stock consumed, then deletes its fixture DB.
"""
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
DEVICE = sys.argv[1] if len(sys.argv) > 1 else "emulator-5556"
ADB = str(Path(os.environ.get("ANDROID_SDK_ROOT", Path.home() / "Library/Android/sdk")) / "platform-tools/adb")
ENV = {**os.environ, "JAVA_HOME": os.environ.get("JAVA_HOME", "/Applications/Android Studio.app/Contents/jbr/Contents/Home")}


def adb(*args):
    return subprocess.check_output([ADB, "-s", DEVICE, *args], text=True).strip()


for stage in ("prepare", "restore", "verify"):
    command = ["flutter", "test", "integration_test/checkout_process_recovery_test.dart",
               "-d", DEVICE, "--no-uninstall", "--reporter", "expanded",
               f"--dart-define=CHECKOUT_PROCESS_STAGE={stage}"]
    process = subprocess.Popen(command, cwd=ROOT, env=ENV, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, bufsize=1)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    ready = False
    deadline = time.monotonic() + 240
    try:
        while time.monotonic() < deadline:
            events = selector.select(timeout=1)
            for key, _ in events:
                line = key.fileobj.readline()
                if not line:
                    break
                print(line, end="", flush=True)
                if f"CHECKOUT_PROCESS_READY {stage}" in line:
                    ready = True
                    break
            if ready or process.poll() is not None:
                break
        if stage == "verify":
            if process.poll() is None:
                process.wait(timeout=30)
            if process.returncode != 0:
                raise RuntimeError(f"verification failed: {process.returncode}")
            print("PASS: actual process death/relaunch preserves draft and exactly-once posting")
        else:
            if not ready:
                raise RuntimeError(f"{stage}: app did not reach persisted checkpoint")
            old_pid = adb("shell", "pidof", "com.storely")
            adb("shell", "am", "force-stop", "com.storely")
            remaining = subprocess.run([ADB, "-s", DEVICE, "shell", "pidof", "com.storely"],
                                       capture_output=True, text=True).stdout.strip()
            if not old_pid or remaining:
                raise RuntimeError(f"force-stop failed: before={old_pid}, after={remaining}")
            print(f"FORCE_STOP {stage}: pid {old_pid} terminated; no app process remains", flush=True)
    finally:
        selector.close()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
