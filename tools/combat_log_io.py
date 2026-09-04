#!/usr/bin/env python3
# ============================================================================
# combat_log_io.py — CombatLog 目录 / index / JSONL 共用 IO
# ============================================================================
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

APP_NAME = "Tidekeeper"
INDEX_NAME = "index.json"


def default_log_dir() -> Path:
    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA", "")
        if appdata:
            return Path(appdata) / "Godot" / "app_userdata" / APP_NAME / "combat_logs"
    home = Path.home()
    for candidate in (
        home / ".local" / "share" / "godot" / "app_userdata" / APP_NAME / "combat_logs",
        home / "Library" / "Application Support" / "Godot" / "app_userdata" / APP_NAME / "combat_logs",
    ):
        if candidate.is_dir():
            return candidate
    return home / ".local" / "share" / "godot" / "app_userdata" / APP_NAME / "combat_logs"


def load_index(dir_path: Path) -> Dict[str, Any]:
    path = dir_path / INDEX_NAME
    if not path.is_file():
        return {"version": 1, "runs": []}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"version": 1, "runs": []}


def _is_under(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except (ValueError, OSError):
        return False


def resolve_run_path(dir_path: Path, row: Dict[str, Any]) -> Optional[Path]:
    """Resolve a run JSONL path; only allow files under dir_path."""
    raw = str(row.get("path", "") or "")
    rid = str(row.get("id", "") or "")
    candidates: List[Path] = []
    if raw:
        if raw.startswith("user://"):
            # user://combat_logs/foo.jsonl → dir/foo.jsonl
            candidates.append(dir_path / Path(raw).name)
        else:
            candidates.append(Path(raw))
    if rid:
        # basename only — ignore any path separators in id
        candidates.append(dir_path / f"{Path(rid).name}.jsonl")

    try:
        root = dir_path.resolve()
    except OSError:
        return None

    for c in candidates:
        try:
            resolved = c.resolve()
        except OSError:
            continue
        if not _is_under(resolved, root):
            continue
        if resolved.is_file():
            return resolved
    return None


def iter_events(path: Path) -> Iterable[Dict[str, Any]]:
    with path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                yield obj


def fmt_seed(seed: Any) -> str:
    if seed is None:
        return "?"
    if isinstance(seed, float):
        return str(int(seed))
    return str(seed)
