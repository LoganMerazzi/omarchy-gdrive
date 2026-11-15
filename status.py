"""Google Drive (rclone) status for the logan.gdrive bar widget.

Usage: status.py <remote> <mount_dir> <recent_limit>
Prints one JSON object. Network calls (rclone about / lsjson) are cached so
opening the panel repeatedly doesn't hammer the Drive API.
"""

import json
import re
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
STATE_DIR = CACHE_DIR / "omarchy-gdrive"
RCLONE_CACHE = CACHE_DIR / "rclone"
ABOUT_TTL = 600
FOLDERS_TTL = 600


def rclone_configured(remote):
  conf_dir = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
  conf = Path(os.environ.get("RCLONE_CONFIG", conf_dir / "rclone" / "rclone.conf"))
  try:
    return f"[{remote}]" in conf.read_text(encoding="utf-8").splitlines()
  except OSError:
    return False


def run_json(command, timeout):
  try:
    completed = subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
  except (OSError, subprocess.TimeoutExpired):
    return None
  if completed.returncode != 0:
    return None
  try:
    return json.loads(completed.stdout)
  except json.JSONDecodeError:
    return None


def cached(name, ttl, producer):
  path = STATE_DIR / name
  try:
    if time.time() - path.stat().st_mtime < ttl:
      return json.loads(path.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError):
    pass
  value = producer()
  if value is not None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")
    return value
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError):
    return None


def list_folders(remote, mount_dir, mounted):
  if mounted:
    try:
      names = [e.name for e in os.scandir(mount_dir) if e.is_dir(follow_symlinks=False)]
    except OSError:
      names = []
  else:
    entries = cached("folders.json", FOLDERS_TTL,
                     lambda: run_json(["rclone", "lsjson", "--dirs-only", f"{remote}:"], 15)) or []
    names = [e.get("Name", "") for e in entries if e.get("IsDir")]
  names = sorted((n for n in names if n), key=str.casefold)
  return [{"name": n, "path": str(Path(mount_dir) / n)} for n in names]


def parse_time(value):
  # rclone writes RFC3339 with nanoseconds; Python only takes microseconds.
  if not value:
    return 0
  text = re.sub(r"(\.\d{6})\d+", r"\1", str(value)).replace("Z", "+00:00")
  try:
    return datetime.fromisoformat(text).timestamp()
  except ValueError:
    return 0


def scan_cache(remote, mount_dir, limit):
  """Files rclone has cached locally (= opened recently), plus pending uploads."""
  items = []
  pending = 0
  cache_bytes = 0
  # Backend overrides on the mount make rclone suffix the cache dir, e.g. "gdrive{f8sEB}".
  for meta_root in cache_roots("vfsMeta", remote):
    data_root = RCLONE_CACHE / "vfs" / meta_root.name
    p, b = scan_root(meta_root, data_root, mount_dir, items)
    pending += p
    cache_bytes += b
  items.sort(key=lambda i: i["accessedTs"], reverse=True)
  return items[:limit], pending, cache_bytes


def cache_roots(kind, remote):
  base = RCLONE_CACHE / kind
  try:
    return [d for d in base.iterdir() if d.is_dir() and (d.name == remote or d.name.startswith(remote + "{"))]
  except OSError:
    return []


def scan_root(meta_root, data_root, mount_dir, items):
  pending = 0
  for dirpath, _dirs, files in os.walk(meta_root):
    for fname in files:
      meta_path = Path(dirpath) / fname
      rel = meta_path.relative_to(meta_root)
      try:
        info = json.loads(meta_path.read_text(encoding="utf-8"))
      except (OSError, json.JSONDecodeError):
        continue
      dirty = bool(info.get("Dirty"))
      if dirty:
        pending += 1
      if not (data_root / rel).exists():
        continue
      items.append({
        "name": rel.name,
        "path": str(Path(mount_dir) / rel),
        "folder": str(rel.parent) if str(rel.parent) != "." else "",
        "accessedTs": parse_time(info.get("ATime")) or parse_time(info.get("ModTime")),
        "dirty": dirty,
      })

  cache_bytes = 0
  for dirpath, _dirs, files in os.walk(data_root):
    for fname in files:
      try:
        cache_bytes += os.lstat(os.path.join(dirpath, fname)).st_blocks * 512
      except OSError:
        pass
  return pending, cache_bytes


def main():
  remote = sys.argv[1] if len(sys.argv) > 1 else "gdrive"
  mount_dir = os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else "~/GoogleDrive")
  limit = int(sys.argv[3]) if len(sys.argv) > 3 else 12

  installed = shutil.which("rclone") is not None
  configured = installed and rclone_configured(remote)
  mounted = os.path.ismount(mount_dir)

  result = {
    "ok": True,
    "installed": installed,
    "configured": configured,
    "mounted": mounted,
    "mountDir": mount_dir,
    "usedBytes": 0,
    "totalBytes": 0,
    "quotaKnown": False,
    "cacheBytes": 0,
    "pendingUploads": 0,
    "folders": [],
    "recent": [],
  }

  if configured:
    about = cached("about.json", ABOUT_TTL, lambda: run_json(["rclone", "about", "--json", f"{remote}:"], 15))
    if about:
      result["usedBytes"] = about.get("used", 0)
      result["totalBytes"] = about.get("total", 0)
      result["quotaKnown"] = bool(about.get("total"))
    result["folders"] = list_folders(remote, mount_dir, mounted)
    result["recent"], result["pendingUploads"], result["cacheBytes"] = scan_cache(remote, mount_dir, limit)

  print(json.dumps(result))


if __name__ == "__main__":
  main()
