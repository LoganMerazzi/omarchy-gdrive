"""Google Drive (rclone) status for the logan.gdrive bar widget.

Usage: status.py <remote> <mount_dir> <starred_limit>
Prints one JSON object. Network calls (rclone about / lsjson / starred query)
are cached so opening the panel repeatedly doesn't hammer the Drive API. When a
call fails (offline, rate limit) the last good cached value is used instead.
"""

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
STATE_DIR = CACHE_DIR / "omarchy-gdrive"
RCLONE_CACHE = CACHE_DIR / "rclone"
ABOUT_TTL = 600
FOLDERS_TTL = 600
STARRED_TTL = 600
NODE_TTL = 86400  # folder name/parent lookups used to build starred paths
FOLDER_MIME = "application/vnd.google-apps.folder"


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


def load_json(name):
  try:
    return json.loads((STATE_DIR / name).read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError):
    return None


def save_json(name, value):
  STATE_DIR.mkdir(parents=True, exist_ok=True)
  (STATE_DIR / name).write_text(json.dumps(value), encoding="utf-8")


def access_token(remote):
  # rclone refreshes and saves the OAuth token whenever it talks to the remote
  # (the starred query runs right before this), so the stored one is current.
  conf = run_json(["rclone", "config", "dump"], 10) or {}
  try:
    return json.loads(conf[remote]["token"])["access_token"]
  except (KeyError, TypeError, ValueError):
    return None


def drive_get(token, file_id):
  # curl rather than urllib: curl falls back to IPv4 at once (happy eyeballs),
  # urllib tries every IPv6 address in turn and stalls on networks without it.
  # The token goes in via stdin so it never shows up in the process list.
  url = (f"https://www.googleapis.com/drive/v3/files/{quote(file_id)}"
         "?fields=id,name,parents&supportsAllDrives=true")
  completed = subprocess.run(["curl", "-sSf", "-m", "8", "-H", "@-", url],
                             input=f"Authorization: Bearer {token}\n",
                             capture_output=True, text=True, timeout=12, check=False)
  if completed.returncode != 0:
    raise LookupError(completed.stderr.strip() or "drive request failed")
  return json.loads(completed.stdout)


def starred_folders(remote):
  """Starred folders with their path inside the mount ("" when outside My Drive).

  rclone can list starred items but only returns parent IDs, and walking the
  whole Drive to map IDs to paths takes minutes. So each parent chain is resolved
  with one files.get per ancestor, memoised in nodes.json for a day.
  Returns None on any failure so the caller keeps the previous result.
  """
  query = f"starred = true and trashed = false and mimeType = '{FOLDER_MIME}'"
  entries = run_json(["rclone", "backend", "query", f"{remote}:", query], 20)
  if entries is None:
    return None

  now = time.time()
  nodes = load_json("nodes.json") or {}
  token = None

  def node(file_id):
    nonlocal token
    cached_node = nodes.get(file_id)
    if cached_node and now - cached_node.get("ts", 0) < NODE_TTL:
      return cached_node
    token = token or access_token(remote)
    if not token:
      raise LookupError("no token")
    info = drive_get(token, file_id)
    cached_node = {"id": info.get("id", file_id), "name": info.get("name", ""),
                   "parents": info.get("parents") or [], "ts": now}
    nodes[file_id] = cached_node
    return cached_node

  result = []
  try:
    root_id = node("root")["id"] if entries else ""
    for e in entries:
      parts = [e.get("name", "")]
      parents = e.get("parents") or []
      rel = None
      for _ in range(64):  # guard against cycles
        if not parents:
          break
        if parents[0] == root_id:
          rel = "/".join(reversed(parts))
          break
        parent = node(parents[0])
        parts.append(parent["name"])
        parents = parent["parents"]
      result.append({"name": e.get("name", ""), "rel": rel or "", "webUrl": e.get("webViewLink", "")})
  except (OSError, subprocess.TimeoutExpired, LookupError, ValueError):
    return None
  finally:
    save_json("nodes.json", nodes)

  result.sort(key=lambda f: f["name"].casefold())
  return result


def scan_cache(remote):
  """Size of rclone's local VFS cache, plus pending uploads."""
  pending = 0
  cache_bytes = 0
  # Backend overrides on the mount make rclone suffix the cache dir, e.g. "gdrive{f8sEB}".
  for meta_root in cache_roots("vfsMeta", remote):
    data_root = RCLONE_CACHE / "vfs" / meta_root.name
    p, b = scan_root(meta_root, data_root)
    pending += p
    cache_bytes += b
  return pending, cache_bytes


def cache_roots(kind, remote):
  base = RCLONE_CACHE / kind
  try:
    return [d for d in base.iterdir() if d.is_dir() and (d.name == remote or d.name.startswith(remote + "{"))]
  except OSError:
    return []


def scan_root(meta_root, data_root):
  pending = 0
  for dirpath, _dirs, files in os.walk(meta_root):
    for fname in files:
      try:
        info = json.loads((Path(dirpath) / fname).read_text(encoding="utf-8"))
      except (OSError, json.JSONDecodeError):
        continue
      if info.get("Dirty"):
        pending += 1

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
  limit = int(sys.argv[3]) if len(sys.argv) > 3 else 20

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
    "starred": [],
  }

  if configured:
    about = cached("about.json", ABOUT_TTL, lambda: run_json(["rclone", "about", "--json", f"{remote}:"], 15))
    if about:
      result["usedBytes"] = about.get("used", 0)
      result["totalBytes"] = about.get("total", 0)
      result["quotaKnown"] = bool(about.get("total"))
    result["folders"] = list_folders(remote, mount_dir, mounted)
    starred = cached("starred.json", STARRED_TTL, lambda: starred_folders(remote)) or []
    result["starred"] = [{
      "name": f["name"],
      "path": str(Path(mount_dir) / f["rel"]) if f["rel"] else "",
      "location": f["rel"].rpartition("/")[0],
      "webUrl": f["webUrl"],
    } for f in starred[:limit]]
    result["pendingUploads"], result["cacheBytes"] = scan_cache(remote)

  print(json.dumps(result))


if __name__ == "__main__":
  main()
