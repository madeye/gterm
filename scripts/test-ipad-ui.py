#!/usr/bin/env python3
"""Run the iPad UI suite on a disposable simulator without opening Simulator.app."""
import argparse
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent


def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def interrupted(signum, frame):
    raise KeyboardInterrupt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data", default=str(ROOT / "build/ui-tests"))
    parser.add_argument("--device-type", default="iPad Pro 11-inch (M5)",
                        help="simctl device type name, e.g. 'iPhone 17 Pro Max' or the "
                             "iPhone Duo simulator once Xcode 27.1 ships")
    parser.add_argument("--only-testing", action="append", default=[],
                        help="xcodebuild -only-testing identifier (repeatable)")
    args = parser.parse_args()
    # Fail before allocating a device if the fixture dependency is missing.
    run(sys.executable, "-c", "import paramiko")
    runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "-j",
                              capture_output=True, text=True).stdout)["runtimes"]
    runtimes = [r for r in runtimes if r["isAvailable"] and r.get("platform") == "iOS"
                and int(r["version"].split(".")[0]) >= 26]
    if not runtimes:
        parser.error("Install an iOS 26 or newer simulator runtime in Xcode.")
    runtime = max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))
    device_types = {d["name"]: d["identifier"] for d in runtime["supportedDeviceTypes"]}
    device_type = device_types.get(args.device_type)
    if device_type is None:
        parser.error(f"No device type {args.device_type!r} in {runtime['name']}. Available:\n  "
                     + "\n  ".join(sorted(device_types)))
    artifacts = Path(tempfile.mkdtemp(prefix="gterm-ui-tests-"))
    print(f"Test logs and screenshots: {artifacts}", flush=True)
    device = None
    fixture = None
    signal.signal(signal.SIGTERM, interrupted)
    try:
        with (artifacts / "ssh.log").open("w") as fixture_log:
            fixture = subprocess.Popen([sys.executable, str(ROOT / "scripts/ipad-ssh-fixture.py")],
                                       stdout=fixture_log, stderr=subprocess.STDOUT)
            for _ in range(100):
                if fixture.poll() is not None:
                    raise RuntimeError(f"SSH fixture failed; see {artifacts / 'ssh.log'}")
                if "READY on" in (artifacts / "ssh.log").read_text():
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError("SSH fixture did not become ready within 10 seconds")
            device = run("xcrun", "simctl", "create", artifacts.name, device_type,
                         runtime["identifier"], capture_output=True, text=True).stdout.strip()
            print(f"Offscreen {args.device_type}: {device} ({runtime['name']})", flush=True)
            # simctl boots the device services without launching the Simulator UI.
            run("xcrun", "simctl", "boot", device)
            run("xcrun", "simctl", "bootstatus", device, "-b")
            run("xcodegen", "generate")
            with (artifacts / "xcodebuild.log").open("w") as build_log:
                only = [arg for test in args.only_testing for arg in ("-only-testing", test)]
                run("xcodebuild", "-project", "gterm.xcodeproj", "-scheme", "gtermUITests",
                    "-destination", f"platform=iOS Simulator,id={device}",
                    "-parallel-testing-enabled", "NO", "-derivedDataPath", args.derived_data,
                    "-resultBundlePath", str(artifacts / "Tests.xcresult"), *only,
                    "CODE_SIGNING_ALLOWED=NO", "test",
                    stdout=build_log, stderr=subprocess.STDOUT)
            print("UI tests passed.", flush=True)
    finally:
        if fixture is not None and fixture.poll() is None:
            fixture.terminate()
            try:
                fixture.wait(timeout=5)
            except subprocess.TimeoutExpired:
                fixture.kill()
                fixture.wait()
        if device:
            subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
            subprocess.run(["xcrun", "simctl", "delete", device], check=False)
        print(f"Results retained at {artifacts}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
