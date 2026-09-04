#!/usr/bin/env python3
# ============================================================================
# view_combat_logs.py — 查看 CombatLog 落盘的局次 JSONL
#
# 路径默认：%APPDATA%/Godot/app_userdata/Tidekeeper/combat_logs/
# （与 config/combat_log.json 的 dir=user://combat_logs/ 对应）
#
# 用法：
#   python tools/view_combat_logs.py
#   python tools/view_combat_logs.py --latest 5
#   python tools/view_combat_logs.py --detail
#   python tools/view_combat_logs.py --run run_20260904_...
#   python tools/view_combat_logs.py --cat damage,upgrade,event
#   python tools/view_combat_logs.py --dir path/to/combat_logs
# ============================================================================
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

_TOOLS_DIR = Path(__file__).resolve().parent
if str(_TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOLS_DIR))

from combat_log_io import (  # noqa: E402
    default_log_dir,
    fmt_seed,
    iter_events,
    load_index,
    resolve_run_path,
)


def _summarize_run(path: Path) -> Dict[str, Any]:
    summary: Dict[str, Any] = {
        "events": 0,
        "cats": {},
        "max_night": 0,
        "level_end": 0,
        "outcome": "?",
        "character": "",
        "seed": None,
        "upgrades": 0,
        "chests": 0,
        "damage_taken_hits": 0,
        "damage_dealt_total": 0,
        "events_armed": [],
        "deaths_logged": 0,
        "spawns_logged": 0,
        "moves": 0,
    }
    for ev in iter_events(path):
        summary["events"] += 1
        cat = str(ev.get("cat", ""))
        summary["cats"][cat] = int(summary["cats"].get(cat, 0)) + 1
        night = int(ev.get("night", 0) or 0)
        if night > summary["max_night"]:
            summary["max_night"] = night
        data = ev.get("data") if isinstance(ev.get("data"), dict) else {}
        action = str(data.get("action", ""))
        if cat == "run" and action == "start":
            summary["character"] = str(data.get("character", ""))
            summary["seed"] = data.get("seed")
        if cat == "run" and action == "end":
            summary["outcome"] = str(data.get("outcome", "?"))
            summary["level_end"] = int(data.get("level", 0) or 0)
        if cat == "upgrade" and action in ("pick", "skip"):
            summary["upgrades"] += 1
        if cat == "chest" and action == "open":
            summary["chests"] += 1
        if cat == "damage" and action == "taken":
            summary["damage_taken_hits"] += 1
        if cat == "damage" and action == "dealt_agg":
            summary["damage_dealt_total"] += int(data.get("total", 0) or 0)
        if cat == "event" and action == "armed":
            summary["events_armed"].append(
                f"N{data.get('for_night', '?')}:{data.get('id', '?')}"
            )
        if cat == "monster" and action == "death":
            summary["deaths_logged"] += 1
        if cat == "monster" and action == "death_agg":
            summary["deaths_logged"] += int(data.get("killed_total", 0) or 0)
        if cat == "monster" and action == "spawn":
            summary["spawns_logged"] += 1
        if cat == "movement":
            summary["moves"] += 1
    return summary


def _print_table(runs: List[Dict[str, Any]], dir_path: Path) -> None:
    print(f"CombatLog dir: {dir_path}")
    print(f"indexed runs: {len(runs)}")
    print("-" * 88)
    print(
        f"{'#':>3}  {'outcome':<12}  {'N':>3}  {'lv':>3}  {'char':<10}  {'seed':<12}  {'events':>6}  id"
    )
    print("-" * 88)
    for i, row in enumerate(runs, 1):
        path = resolve_run_path(dir_path, row)
        sm = _summarize_run(path) if path else {}
        outcome = str(row.get("outcome") or sm.get("outcome") or "?")
        nights = int(row.get("nights") or sm.get("max_night") or 0)
        level = int(sm.get("level_end") or 0)
        char = str(row.get("character") or sm.get("character") or "?")
        seed = row.get("seed", sm.get("seed"))
        seed_s = fmt_seed(seed)
        ev_n = int(sm.get("events") or 0)
        rid = str(row.get("id", "?"))
        print(
            f"{i:>3}  {outcome:<12}  {nights:>3}  {level:>3}  {char:<10}  {seed_s:<12}  {ev_n:>6}  {rid}"
        )


def _print_detail(path: Path, cats: Optional[Set[str]]) -> None:
    print(f"\n=== {path.name} ===")
    sm = _summarize_run(path)
    print(
        f"outcome={sm['outcome']} nights={sm['max_night']} lv={sm['level_end']} "
        f"char={sm['character']} seed={sm['seed']}"
    )
    print(
        f"upgrades={sm['upgrades']} chests={sm['chests']} "
        f"dmg_taken_hits={sm['damage_taken_hits']} dmg_dealt≈{sm['damage_dealt_total']} "
        f"spawns={sm['spawns_logged']} deaths={sm['deaths_logged']} moves={sm['moves']}"
    )
    if sm["events_armed"]:
        print("events: " + ", ".join(sm["events_armed"]))
    print("cats:", ", ".join(f"{k}={v}" for k, v in sorted(sm["cats"].items())))
    print("-" * 72)
    for ev in iter_events(path):
        cat = str(ev.get("cat", ""))
        if cats and cat not in cats:
            continue
        t = ev.get("t", 0)
        night = ev.get("night", 0)
        data = ev.get("data", {})
        action = data.get("action", "") if isinstance(data, dict) else ""
        compact = data if isinstance(data, dict) else {"raw": data}
        body = {k: v for k, v in compact.items() if k != "action"}
        print(f"t={t:>7} N{night:<2} [{cat}:{action}] {json.dumps(body, ensure_ascii=True)}")


def main() -> int:
    ap = argparse.ArgumentParser(description="View Tidekeeper CombatLog JSONL runs")
    ap.add_argument("--dir", type=str, default="", help="combat_logs directory")
    ap.add_argument("--latest", type=int, default=10, help="show latest N index entries")
    ap.add_argument("--detail", action="store_true", help="print event lines")
    ap.add_argument("--run", type=str, default="", help="filter by run id substring")
    ap.add_argument(
        "--cat",
        type=str,
        default="",
        help="comma-separated categories when --detail (e.g. damage,upgrade)",
    )
    args = ap.parse_args()

    dir_path = Path(args.dir) if args.dir else default_log_dir()
    if not dir_path.is_dir():
        print(f"No combat log dir: {dir_path}", file=sys.stderr)
        print("Play a non-headless run (debug.bat) first.", file=sys.stderr)
        return 1

    index = load_index(dir_path)
    raw_runs: List[Dict[str, Any]] = list(index.get("runs") or [])
    runs: List[Dict[str, Any]] = list(raw_runs)
    if args.run:
        needle = args.run.lower()
        runs = [r for r in runs if needle in str(r.get("id", "")).lower()]
    if args.latest > 0 and len(runs) > args.latest:
        runs = runs[-args.latest :]

    if not runs:
        # Filtered miss (or empty after --latest) must not dump every jsonl.
        if raw_runs or args.run:
            print(f"No matching runs in {dir_path}")
            return 0
        files = sorted(dir_path.glob("run_*.jsonl"))
        if not files:
            print(f"No runs in {dir_path}")
            return 0
        print(f"No index; found {len(files)} jsonl files under {dir_path}")
        for f in files[-args.latest :] if args.latest > 0 else files:
            if args.detail:
                cats = set(c.strip() for c in args.cat.split(",") if c.strip()) or None
                _print_detail(f, cats)
            else:
                sm = _summarize_run(f)
                print(
                    f"{f.name}  outcome={sm['outcome']} N={sm['max_night']} "
                    f"events={sm['events']}"
                )
        return 0

    _print_table(runs, dir_path)
    if args.detail:
        cats = set(c.strip() for c in args.cat.split(",") if c.strip()) or None
        for row in runs:
            path = resolve_run_path(dir_path, row)
            if path:
                _print_detail(path, cats)
    return 0



if __name__ == "__main__":
    raise SystemExit(main())
