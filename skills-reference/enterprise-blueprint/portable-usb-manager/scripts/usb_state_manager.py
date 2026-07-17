#!/usr/bin/env python3
"""
USB State Manager - Persistent device tracking across reboots.

Tracks USB devices by UUID, maintains mount history, and provides
device tagging and search capabilities.

Usage:
    python3 usb_state_manager.py --list
    python3 usb_state_manager.py --history <uuid>
    python3 usb_state_manager.py --tag <uuid> --add "backup"
    python3 usb_state_manager.py --remove <uuid>
    python3 usb_state_manager.py --export state-backup.json
    python3 usb_state_manager.py --import state-backup.json
    python3 usb_state_manager.py --scan
    python3 usb_state_manager.py --dry-run --list
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

VERSION = "1.0.0"
STATE_FILE_USER = os.path.expanduser("~/.usb-state.json")
STATE_FILE_SYSTEM = "/var/lib/usb-state.json"

def get_state_file() -> str:
    if os.access(STATE_FILE_SYSTEM, os.W_OK):
        return STATE_FILE_SYSTEM
    return STATE_FILE_USER

def load_state(path: str) -> Dict[str, Any]:
    if os.path.exists(path):
        with open(path, "r") as f:
            return json.load(f)
    return {
        "version": VERSION,
        "last_updated": "",
        "devices": {},
        "mount_history": []
    }

def save_state(path: str, state: Dict[str, Any], dry_run: bool = False) -> None:
    state["last_updated"] = datetime.now(timezone.utc).isoformat()
    if dry_run:
        print(json.dumps({"action": "save", "path": path, "dry_run": True}, indent=2))
        return
    with open(path, "w") as f:
        json.dump(state, f, indent=2)

def detect_usb_devices() -> List[Dict[str, str]]:
    devices = []
    try:
        result = subprocess.run(
            ["lsblk", "-J", "-o", "NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,TRAN,MODEL"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return devices
        data = json.loads(result.stdout)

        parent_tran = {}
        for device in data.get("blockdevices", []):
            disk_name = device.get("name", "")
            disk_tran = device.get("tran", "") or ""
            if device.get("type") == "disk" and "usb" in disk_tran.lower():
                for child in device.get("children", []):
                    parent_tran[child.get("name", "")] = disk_name
                    for grandchild in child.get("children", []):
                        parent_tran[grandchild.get("name", "")] = disk_name

        for device in data.get("blockdevices", []):
            devname = device.get("name", "")
            devtype = device.get("type", "")
            tran = device.get("tran", "") or ""

            if devtype == "disk" and "usb" in tran.lower():
                info = get_device_info(devname)
                devices.append(info)
            elif devtype == "part" and devname in parent_tran:
                info = get_device_info(devname)
                devices.append(info)
            for child in device.get("children", []):
                child_name = child.get("name", "")
                child_type = child.get("type", "")
                if child_type == "part" and child_name in parent_tran:
                    info = get_device_info(child_name)
                    devices.append(info)
                for grandchild in child.get("children", []):
                    gc_name = grandchild.get("name", "")
                    gc_type = grandchild.get("type", "")
                    if gc_type == "part" and gc_name in parent_tran:
                        info = get_device_info(gc_name)
                        devices.append(info)
    except Exception:
        pass
    return devices

def get_device_info(devname: str) -> Dict[str, str]:
    info = {
        "device": f"/dev/{devname}",
        "name": devname,
        "filesystem": "",
        "label": "",
        "uuid": "",
        "size": "",
        "model": "",
        "vendor": ""
    }
    try:
        result = subprocess.run(
            ["blkid", "-o", "value", "-s", "TYPE", f"/dev/{devname}"],
            capture_output=True, text=True, timeout=5
        )
        info["filesystem"] = result.stdout.strip()
    except Exception:
        pass
    try:
        result = subprocess.run(
            ["blkid", "-o", "value", "-s", "LABEL", f"/dev/{devname}"],
            capture_output=True, text=True, timeout=5
        )
        info["label"] = result.stdout.strip()
    except Exception:
        pass
    try:
        result = subprocess.run(
            ["blkid", "-o", "value", "-s", "UUID", f"/dev/{devname}"],
            capture_output=True, text=True, timeout=5
        )
        info["uuid"] = result.stdout.strip()
    except Exception:
        pass
    try:
        result = subprocess.run(
            ["lsblk", "-nd", "-o", "SIZE", f"/dev/{devname}"],
            capture_output=True, text=True, timeout=5
        )
        info["size"] = result.stdout.strip()
    except Exception:
        pass
    try:
        sysfs = f"/sys/block/{devname.rstrip('0123456789')}/device"
        if os.path.exists(f"{sysfs}/model"):
            with open(f"{sysfs}/model") as f:
                info["model"] = f.read().strip()
        if os.path.exists(f"{sysfs}/vendor"):
            with open(f"{sysfs}/vendor") as f:
                info["vendor"] = f.read().strip()
    except Exception:
        pass
    return info

def add_history(state: Dict[str, Any], event: str, device_uuid: str, details: Dict[str, Any] = None) -> None:
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "event": event,
        "device_uuid": device_uuid,
        "details": details or {}
    }
    state["mount_history"].append(entry)
    if len(state["mount_history"]) > 1000:
        state["mount_history"] = state["mount_history"][-1000:]

def cmd_list(args, state):
    if not state["devices"]:
        print("No devices tracked.")
        return
    print(f"{'UUID':<38} {'Device':<12} {'Label':<16} {'FS':<8} {'Size':<10} {'Last Seen'}")
    print("-" * 110)
    for uuid, dev in state["devices"].items():
        last_seen = dev.get("last_seen", "never")[:10]
        print(f"{uuid:<38} {dev.get('device',''):<12} {dev.get('label',''):<16} {dev.get('filesystem',''):<8} {dev.get('size_bytes',0):>10} {last_seen}")

def cmd_history(args, state):
    uuid = args.history
    entries = [h for h in state["mount_history"] if h["device_uuid"] == uuid]
    if not entries:
        print(f"No history for {uuid}")
        return
    for e in entries[-20:]:
        print(f"{e['timestamp'][:19]}  {e['event']:<12}  {e.get('details', {})}")

def cmd_tag(args, state):
    uuid = args.tag
    if uuid not in state["devices"]:
        print(f"Device {uuid} not found")
        return
    dev = state["devices"][uuid]
    tags = dev.get("tags", [])
    if args.add:
        for t in args.add:
            if t not in tags:
                tags.append(t)
    if args.remove_tag:
        tags = [t for t in tags if t not in args.remove_tag]
    dev["tags"] = tags
    print(f"Tags for {uuid}: {tags}")

def cmd_remove(args, state):
    uuid = args.remove
    if uuid in state["devices"]:
        del state["devices"][uuid]
        print(f"Removed {uuid}")
    else:
        print(f"Device {uuid} not found")

def cmd_export(args, state):
    output = args.export or "usb-state-export.json"
    with open(output, "w") as f:
        json.dump(state, f, indent=2)
    print(f"Exported to {output}")

def cmd_import(args, state):
    with open(args.import_file, "r") as f:
        imported = json.load(f)
    state["devices"].update(imported.get("devices", {}))
    state["mount_history"].extend(imported.get("mount_history", []))
    print(f"Imported {len(imported.get('devices', {}))} devices")

def cmd_scan(args, state):
    devices = detect_usb_devices()
    now = datetime.now(timezone.utc).isoformat()
    for dev in devices:
        uuid = dev.get("uuid", "")
        if not uuid:
            continue
        if uuid in state["devices"]:
            state["devices"][uuid]["last_seen"] = now
            state["devices"][uuid]["device"] = dev["device"]
        else:
            state["devices"][uuid] = {
                "device": dev["device"],
                "uuid": uuid,
                "label": dev.get("label", ""),
                "filesystem": dev.get("filesystem", ""),
                "size_bytes": 0,
                "model": dev.get("model", ""),
                "vendor": dev.get("vendor", ""),
                "first_seen": now,
                "last_seen": now,
                "last_mount_point": "",
                "mount_count": 0,
                "health_status": "unknown",
                "tags": []
            }
        add_history(state, "scan", uuid, {"device": dev["device"]})
    print(f"Scanned {len(devices)} USB device(s), {len(state['devices'])} total tracked")

def main():
    parser = argparse.ArgumentParser(description="USB State Manager")
    parser.add_argument("--list", action="store_true", help="List tracked devices")
    parser.add_argument("--history", metavar="UUID", help="Show device history")
    parser.add_argument("--tag", metavar="UUID", help="Tag device")
    parser.add_argument("--add", nargs="+", help="Tags to add")
    parser.add_argument("--remove-tag", nargs="+", dest="remove_tag", help="Tags to remove")
    parser.add_argument("--remove", metavar="UUID", help="Remove device from tracking")
    parser.add_argument("--export", metavar="FILE", nargs="?", const="usb-state-export.json", help="Export state")
    parser.add_argument("--import-file", metavar="FILE", dest="import_file", help="Import state")
    parser.add_argument("--scan", action="store_true", help="Scan for USB devices")
    parser.add_argument("--dry-run", action="store_true", help="Show what would happen")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    state_file = get_state_file()
    state = load_state(state_file)

    if args.list:
        if args.json:
            print(json.dumps(state["devices"], indent=2))
        else:
            cmd_list(args, state)
    elif args.history:
        cmd_history(args, state)
    elif args.tag:
        cmd_tag(args, state)
    elif args.remove:
        cmd_remove(args, state)
    elif args.export is not None:
        cmd_export(args, state)
    elif args.import_file:
        cmd_import(args, state)
    elif args.scan:
        cmd_scan(args, state)
    else:
        parser.print_help()

    save_state(state_file, state, args.dry_run)

    output = {
        "operation": "state",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "status": "success",
        "details": {"devices_tracked": len(state["devices"])},
        "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
    }
    print(json.dumps(output, indent=2))

if __name__ == "__main__":
    main()
