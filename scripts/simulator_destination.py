#!/usr/bin/env python3
"""Choose an installed iPhone for local verification, preferring a booted device."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def destination(payload):
    candidates = []
    prefix = "com.apple.CoreSimulator.SimRuntime.iOS-"
    for runtime, devices in payload.get("devices", {}).items():
        if not runtime.startswith(prefix):
            continue
        try:
            version = tuple(int(part) for part in runtime[len(prefix):].split("-"))
        except ValueError:
            continue
        for device in devices:
            name, identifier = device.get("name", ""), device.get("udid")
            if name.startswith("iPhone") and identifier and device.get("isAvailable", True):
                candidates.append((device.get("state") == "Booted", version, name, identifier))
    if not candidates:
        raise ValueError("No installed iPhone simulator. Install an iOS runtime in Xcode or set TIKDOG_TEST_DESTINATION.")
    return "platform=iOS Simulator,id=" + max(candidates)[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--devices-json", type=Path, help="Read a saved simctl device inventory instead of querying Xcode")
    args = parser.parse_args()
    try:
        raw = args.devices_json.read_text() if args.devices_json else subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
        )
        print(destination(json.loads(raw)))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
