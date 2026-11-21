#!/usr/bin/env python3
"""Read-only Mac/volume inventory. No installs, downloads or server launches."""
import argparse
import json
import platform
import shutil
import subprocess
from pathlib import Path


def read_command(argv):
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=20, check=False)
        if result.returncode:
            return {"value": None, "error": result.stderr.strip() or f"exit {result.returncode}"}
        return {"value": result.stdout.strip(), "error": None}
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"value": None, "error": str(exc)}


def sysctl(key, integer=False):
    result = read_command(["/usr/sbin/sysctl", "-n", key])
    if integer and result["value"] is not None:
        try:
            result["value"] = int(result["value"])
        except ValueError:
            result = {"value": None, "error": f"Non-integer value for {key}"}
    return result


def disk_info(destination):
    requested = Path(destination).expanduser().resolve()
    existing = requested
    while not existing.exists() and existing != existing.parent:
        existing = existing.parent
    if existing.is_file():
        existing = existing.parent
    try:
        usage = shutil.disk_usage(existing)
        return {"requested_directory": str(requested), "measured_ancestor": str(existing),
                "total_bytes": usage.total, "free_bytes": usage.free,
                "free_gib": round(usage.free / 2**30, 2), "error": None}
    except OSError as exc:
        return {"requested_directory": str(requested), "free_bytes": None, "error": str(exc)}


def gpu_info():
    result = read_command(["/usr/sbin/system_profiler", "SPDisplaysDataType", "-json"])
    if result["value"] is None:
        return result
    try:
        devices = json.loads(result["value"]).get("SPDisplaysDataType", [])
        # Do not expose display serials or unrelated profiler fields.
        return {"value": [{key: device[key] for key in
                           ("sppci_model", "sppci_cores", "spdisplays_metal") if key in device}
                          for device in devices], "error": None}
    except (ValueError, TypeError) as exc:
        return {"value": None, "error": str(exc)}


def inspect(destination):
    result = {"platform": platform.system(), "process_architecture": platform.machine(),
              "disk": disk_info(destination)}
    if platform.system() != "Darwin":
        result["supported_host"] = False
        result["note"] = "Current Sushi packs require Apple Silicon macOS; no Mac recipe inferred."
        return result
    keys = {"apple_silicon": ("hw.optional.arm64", True),
            "rosetta_process": ("sysctl.proc_translated", True),
            "chip": ("machdep.cpu.brand_string", False),
            "physical_cpu_cores": ("hw.physicalcpu", True),
            "logical_cpu_cores": ("hw.logicalcpu", True),
            "memory_bytes": ("hw.memsize", True),
            "gpu_wired_limit_mb": ("iogpu.wired_limit_mb", True),
            "swap": ("vm.swapusage", False)}
    result.update({label: sysctl(key, integer) for label, (key, integer) in keys.items()})
    memory = result["memory_bytes"]["value"]
    result["memory_gib"] = round(memory / 2**30, 2) if memory is not None else None
    result["macos"] = read_command(["/usr/bin/sw_vers", "-productVersion"])
    result["gpu"] = gpu_info()
    result["memory_pressure"] = read_command(["/usr/bin/memory_pressure", "-Q"])
    result["vm_stat"] = read_command(["/usr/bin/vm_stat"])
    result["note"] = "Unknown/blocked probes are not zero. This inventory does not prove model fit."
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", default="~/.sushi/models", help="Intended download volume/directory")
    args = parser.parse_args()
    print(json.dumps(inspect(args.model_dir), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
