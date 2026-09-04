#!/usr/bin/env python3
# ============================================================================
# stats_combat_logs.py — CombatLog 局次聚合统计
#
# 路径默认：%APPDATA%/Godot/app_userdata/Tidekeeper/combat_logs/
# （与 config/combat_log.json 的 dir=user://combat_logs/ 对应）
#
# 用法：
#   python tools/stats_combat_logs.py
#   python tools/stats_combat_logs.py --latest 20
#   python tools/stats_combat_logs.py --detail
#   python tools/stats_combat_logs.py --run 105046
#   python tools/stats_combat_logs.py --min-events 50
#   python tools/stats_combat_logs.py --completed-only
#   python tools/stats_combat_logs.py --json
#   python tools/stats_combat_logs.py --dir path/to/combat_logs
#   python tools/stats_combat_logs.py --self-test
# ============================================================================
from __future__ import annotations

import argparse
import json
import sys
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

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

COMPLETED = frozenset({"win", "death"})


def _avg(xs: Sequence[float]) -> float:
    return sum(xs) / len(xs) if xs else 0.0


def _upgrade_id(data: Dict[str, Any]) -> str:
    for key in ("id", "choice", "choice_id", "name", "option"):
        val = data.get(key)
        if val is not None and str(val):
            return str(val)
    return "?"


def analyze_run(row: Dict[str, Any], path: Path) -> Dict[str, Any]:
    """Parse one JSONL run into a stats dict (Counters kept as Counter)."""
    sm: Dict[str, Any] = {
        "id": str(row.get("id") or path.stem),
        "index_outcome": str(row.get("outcome") or ""),
        "bot": False,
        "character": "",
        "seed": None,
        "started_at": "",
        "outcome": "?",
        "level_end": 0,
        "max_night": 0,
        "max_hp_start": 0,
        "events": 0,
        "duration_t": 0.0,
        "upgrades_pick": Counter(),
        "upgrades_pick_n": 0,
        "upgrades_skip": 0,
        "chests_n": 0,
        "chests": [],
        "dmg_taken_hits": 0,
        "dmg_taken_total": 0.0,
        "dmg_taken_by_src": Counter(),
        "dmg_dealt_total": 0,
        "dmg_dealt_by_weapon": Counter(),
        "kills_total": 0,
        "kills_by_id": Counter(),
        "spawns_total": 0,
        "spawns_by_id": Counter(),
        "events_armed": [],
        "evolutions": [],
        "refines": [],
        "final_weapons": [],
        "final_passives": [],
        "final_build": {},
        "final_char": {},
        "death": None,
    }
    last_build: Optional[Dict[str, Any]] = None
    last_char: Optional[Dict[str, Any]] = None
    last_weapon: Optional[Dict[str, Any]] = None

    for ev in iter_events(path):
        sm["events"] += 1
        cat = str(ev.get("cat", ""))
        data = ev.get("data") if isinstance(ev.get("data"), dict) else {}
        action = str(data.get("action", ""))
        night = int(ev.get("night", 0) or 0)
        t = float(ev.get("t", 0) or 0)
        if t > sm["duration_t"]:
            sm["duration_t"] = t
        if night > sm["max_night"]:
            sm["max_night"] = night

        if cat == "run" and action == "start":
            sm["bot"] = bool(data.get("bot"))
            sm["character"] = str(data.get("character", ""))
            sm["seed"] = data.get("seed")
            sm["started_at"] = str(data.get("started_at", ""))
            sm["max_hp_start"] = int(data.get("max_hp", 0) or 0)
        elif cat == "run" and action == "end":
            sm["outcome"] = str(data.get("outcome", "?") or "?")
            sm["level_end"] = int(data.get("level", 0) or 0)
            death = data.get("death")
            if isinstance(death, dict):
                sm["death"] = death
        elif cat == "upgrade" and action == "pick":
            sm["upgrades_pick_n"] += 1
            sm["upgrades_pick"][_upgrade_id(data)] += 1
        elif cat == "upgrade" and action == "skip":
            sm["upgrades_skip"] += 1
        elif cat == "chest" and action == "open":
            sm["chests_n"] += 1
            sm["chests"].append(
                {
                    "night": night,
                    "kind": data.get("kind"),
                    "rarity": data.get("rarity"),
                    "amount": data.get("amount"),
                }
            )
        elif cat == "damage" and action == "taken":
            amount = float(data.get("amount") or data.get("dmg") or data.get("damage") or 0)
            src = str(data.get("source") or data.get("src") or "?")
            sm["dmg_taken_hits"] += 1
            sm["dmg_taken_total"] += amount
            sm["dmg_taken_by_src"][src] += amount
        elif cat == "damage" and action == "dealt_agg":
            sm["dmg_dealt_total"] += int(data.get("total", 0) or 0)
            by_weapon = data.get("by_weapon")
            if isinstance(by_weapon, list):
                for row_w in by_weapon:
                    if isinstance(row_w, dict):
                        wid = str(row_w.get("id") or "?")
                        sm["dmg_dealt_by_weapon"][wid] += int(row_w.get("dealt") or 0)
            elif isinstance(by_weapon, dict):
                for wid, dealt in by_weapon.items():
                    sm["dmg_dealt_by_weapon"][str(wid)] += int(dealt or 0)
        elif cat == "monster" and action == "spawn":
            sm["spawns_total"] += 1
            sm["spawns_by_id"][str(data.get("id", "?"))] += 1
        elif cat == "monster" and action == "death":
            sm["kills_total"] += 1
            sm["kills_by_id"][str(data.get("id", "?"))] += 1
        elif cat == "monster" and action == "death_agg":
            sm["kills_total"] += int(data.get("killed_total", 0) or 0)
            by_id = data.get("by_id") or data.get("kills") or {}
            if isinstance(by_id, dict):
                for mid, n in by_id.items():
                    sm["kills_by_id"][str(mid)] += int(n or 0)
        elif cat == "event" and action == "armed":
            sm["events_armed"].append(f"N{data.get('for_night', '?')}:{data.get('id', '?')}")
        elif cat == "evolution":
            sm["evolutions"].append(dict(data))
        elif cat == "refine":
            sm["refines"].append(dict(data))
        elif cat == "build" and action == "snapshot":
            last_build = data
        elif cat == "character" and action == "snapshot":
            last_char = data
        elif cat == "weapon" and action == "sheet":
            last_weapon = data

    if last_build:
        sm["final_weapons"] = list(last_build.get("weapons") or [])
        sm["final_passives"] = list(last_build.get("passives") or [])
        sm["final_build"] = {
            k: last_build.get(k)
            for k in ("level", "atk_m", "dmg_m", "area_m", "cd_r", "crit", "dr", "exp_m")
            if k in last_build
        }
        if not sm["level_end"]:
            sm["level_end"] = int(last_build.get("level", 0) or 0)
    if last_char:
        sm["final_char"] = {
            k: last_char.get(k)
            for k in (
                "level",
                "hp",
                "max_hp",
                "coins",
                "evo_items",
                "refine_essence",
                "exp",
                "phase",
            )
            if k in last_char
        }
        if not sm["level_end"]:
            sm["level_end"] = int(last_char.get("level", 0) or 0)
    if last_weapon and not sm["final_weapons"]:
        sm["final_weapons"] = list(last_weapon.get("weapons") or [])

    if sm["outcome"] == "?" and sm["index_outcome"]:
        sm["outcome"] = sm["index_outcome"]
    return sm


def _counter_to_dict(c: Counter) -> Dict[str, Any]:
    return {str(k): (int(v) if isinstance(v, int) else float(v)) for k, v in c.most_common()}


def run_to_jsonable(sm: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(sm)
    for key in (
        "upgrades_pick",
        "dmg_taken_by_src",
        "dmg_dealt_by_weapon",
        "kills_by_id",
        "spawns_by_id",
    ):
        out[key] = _counter_to_dict(sm[key])
    return out


def collect_runs(
    dir_path: Path,
    index_runs: List[Dict[str, Any]],
    *,
    fallback_glob: bool = False,
) -> List[Dict[str, Any]]:
    """Load runs from index rows; optionally glob when index is truly empty.

    fallback_glob must stay False after --run/--latest filters emptied a
    non-empty index — otherwise a miss would silently scan all jsonl files.
    """
    result: List[Dict[str, Any]] = []
    if index_runs:
        for row in index_runs:
            path = resolve_run_path(dir_path, row)
            if path:
                result.append(analyze_run(row, path))
        return result
    if not fallback_glob:
        return []
    for path in sorted(dir_path.glob("run_*.jsonl")):
        result.append(analyze_run({"id": path.stem}, path))
    return result


def filter_runs(
    runs: List[Dict[str, Any]],
    *,
    completed_only: bool,
) -> List[Dict[str, Any]]:
    if completed_only:
        return [s for s in runs if s["outcome"] in COMPLETED]
    return runs


def _weapon_label(w: Any) -> str:
    if not isinstance(w, dict):
        return str(w)
    evo = w.get("evo_name") or ("evo" if w.get("evo") else "")
    label = f"{w.get('id')} Lv{w.get('lv')} R{w.get('refine', 0)}"
    if evo:
        label += f"[{evo}]"
    return label


def _passive_label(p: Any) -> str:
    if isinstance(p, dict):
        return f"{p.get('id', p)} Lv{p.get('lv', '?')}"
    return str(p)


def _print_top(title: str, counter: Counter, limit: int = 10, as_float: bool = False) -> None:
    if not counter:
        print(f"{title}: (empty)")
        return
    total = sum(counter.values()) or 1
    print(title)
    for i, (k, v) in enumerate(counter.most_common(limit), 1):
        if as_float:
            print(f"  {i:>2}. {k:<28} {v:>12.0f}  ({100.0 * v / total:5.1f}%)")
        else:
            print(f"  {i:>2}. {k:<28} {v:>12}  ({100.0 * v / total:5.1f}%)")


def print_report(
    all_runs: List[Dict[str, Any]],
    *,
    dir_path: Path,
    min_events: int,
    detail: bool,
    top: int,
) -> None:
    completed = [s for s in all_runs if s["outcome"] in COMPLETED]
    wins = [s for s in completed if s["outcome"] == "win"]
    deaths = [s for s in completed if s["outcome"] == "death"]
    meaningful = [
        s for s in all_runs if s["events"] >= min_events or s["outcome"] in COMPLETED
    ]

    print("=" * 72)
    print("CombatLog stats")
    print(f"dir: {dir_path}")
    print(
        f"shown={len(all_runs)}  meaningful(>={min_events} or win/death)={len(meaningful)}  "
        f"completed_in_shown={len(completed)}"
    )
    print("=" * 72)

    print("\n## Runs")
    print(
        f"{'#':>2} {'outcome':<12} {'bot':<3} {'N':>3} {'lv':>3} {'t_s':>6} "
        f"{'kills':>6} {'hits':>5} {'dmg_out':>10} {'upg':>4} {'seed':<12} started"
    )
    print("-" * 110)
    for i, s in enumerate(all_runs, 1):
        print(
            f"{i:>2} {s['outcome']:<12} {'Y' if s['bot'] else 'N':<3} {s['max_night']:>3} "
            f"{s['level_end']:>3} {s['duration_t']:>6.0f} {s['kills_total']:>6} "
            f"{s['dmg_taken_hits']:>5} {s['dmg_dealt_total']:>10} {s['upgrades_pick_n']:>4} "
            f"{fmt_seed(s['seed']):<12} {s['started_at']}"
        )

    print("\n## Outcome counts (shown)")
    for k, v in Counter(s["outcome"] for s in all_runs).most_common():
        print(f"  {k}: {v}")

    if completed:
        print("\n## Completed aggregate (win+death in shown set)")
        print(
            f"  n={len(completed)}  winrate={len(wins)}/{len(completed)} "
            f"({100.0 * len(wins) / len(completed):.0f}%)"
        )
        print(f"  avg night={_avg([s['max_night'] for s in completed]):.1f}")
        print(f"  avg level={_avg([s['level_end'] for s in completed]):.1f}")
        print(f"  avg kills={_avg([s['kills_total'] for s in completed]):.0f}")
        print(f"  avg dmg_out={_avg([s['dmg_dealt_total'] for s in completed]):.0f}")
        print(f"  avg taken_hits={_avg([s['dmg_taken_hits'] for s in completed]):.0f}")
        print(f"  avg taken_total={_avg([s['dmg_taken_total'] for s in completed]):.0f}")
        print(f"  avg duration_s={_avg([s['duration_t'] for s in completed]):.0f}")
        print(f"  avg upgrades={_avg([s['upgrades_pick_n'] for s in completed]):.1f}")
        print(
            f"  win nights={[s['max_night'] for s in wins]} "
            f"levels={[s['level_end'] for s in wins]}"
        )
        print(
            f"  death nights={[s['max_night'] for s in deaths]} "
            f"levels={[s['level_end'] for s in deaths]}"
        )

        dmg_w: Counter = Counter()
        taken: Counter = Counter()
        upgrades: Counter = Counter()
        kills: Counter = Counter()
        spawns: Counter = Counter()
        last_hit: Counter = Counter()
        death_top: Counter = Counter()
        for s in completed:
            dmg_w.update(s["dmg_dealt_by_weapon"])
            taken.update(s["dmg_taken_by_src"])
            upgrades.update(s["upgrades_pick"])
            kills.update(s["kills_by_id"])
            spawns.update(s["spawns_by_id"])
            death = s.get("death")
            if isinstance(death, dict):
                last_hit[str(death.get("last_hit_source") or "?")] += 1
                for row in death.get("top_sources") or []:
                    if isinstance(row, dict):
                        death_top[str(row.get("source") or "?")] += float(
                            row.get("damage") or 0
                        )

        print()
        _print_top("## Weapon damage (completed)", dmg_w, top)
        print()
        _print_top("## Damage taken by source (completed)", taken, top, as_float=True)
        print()
        _print_top("## Upgrade picks (completed)", upgrades, top)
        if kills:
            print()
            _print_top(
                "## Kill samples by_id (completed; may be sparse if death_agg)",
                kills,
                top,
            )
        if spawns:
            print()
            _print_top("## Spawn samples (completed)", spawns, top)
        if last_hit:
            print()
            _print_top("## Death last_hit_source", last_hit, top)
        if death_top:
            print()
            _print_top("## Death top_sources damage sum", death_top, top, as_float=True)

    if detail:
        focus = meaningful
        print("\n" + "=" * 72)
        print("## Run details")
        print("=" * 72)
        for s in focus:
            print(f"\n### {s['id']}")
            print(
                f"  outcome={s['outcome']} bot={s['bot']} char={s['character']} "
                f"seed={fmt_seed(s['seed'])}"
            )
            print(
                f"  night={s['max_night']} lv_end={s['level_end']} (run_end) "
                f"t={s['duration_t']:.0f}s events={s['events']}"
            )
            print(
                f"  start_maxHP={s['max_hp_start']} kills={s['kills_total']} "
                f"spawn_samples={s['spawns_total']}"
            )
            print(
                f"  taken: {s['dmg_taken_hits']} hits / ~{s['dmg_taken_total']:.0f}  "
                f"dealt~{s['dmg_dealt_total']}"
            )
            fc = s["final_char"]
            if fc:
                print(
                    f"  last char snapshot: lv={fc.get('level')} "
                    f"hp={fc.get('hp')}/{fc.get('max_hp')} "
                    f"coins={fc.get('coins')} evo={fc.get('evo_items')} "
                    f"refine={fc.get('refine_essence')} phase={fc.get('phase')}"
                )
            fb = s["final_build"]
            if fb:
                print(
                    f"  last BD snapshot: atk={fb.get('atk_m')} dmg={fb.get('dmg_m')} "
                    f"area={fb.get('area_m')} cd_r={fb.get('cd_r')} crit={fb.get('crit')} "
                    f"dr={fb.get('dr')} exp={fb.get('exp_m')}"
                )
            if s["final_weapons"]:
                print("  weapons: " + ", ".join(_weapon_label(w) for w in s["final_weapons"]))
            if s["final_passives"]:
                print(
                    "  passives: " + ", ".join(_passive_label(p) for p in s["final_passives"])
                )
            if s["evolutions"]:
                evo_s = ", ".join(
                    f"{e.get('weapon_id')}->{e.get('evolved_name')}"
                    for e in s["evolutions"]
                    if isinstance(e, dict)
                )
                print(f"  evolutions: {evo_s or s['evolutions']}")
            if s["refines"]:
                ref_s = ", ".join(
                    f"{r.get('weapon_id')} T{r.get('tier')} {r.get('path')}"
                    for r in s["refines"]
                    if isinstance(r, dict)
                )
                print(f"  refines: {ref_s or s['refines']}")
            if s["events_armed"]:
                print("  events: " + ", ".join(s["events_armed"]))
            if s["chests"]:
                shown = ", ".join(
                    f"N{c['night']}:{c['kind']}/{c['rarity']}x{c.get('amount')}"
                    for c in s["chests"][:12]
                )
                more = " ..." if len(s["chests"]) > 12 else ""
                print(f"  chests({s['chests_n']}): {shown}{more}")
            if s["dmg_dealt_by_weapon"]:
                top_w = s["dmg_dealt_by_weapon"].most_common(5)
                print("  dmg top: " + ", ".join(f"{k}={v}" for k, v in top_w))
            if s["dmg_taken_by_src"]:
                top_t = s["dmg_taken_by_src"].most_common(5)
                print("  taken top: " + ", ".join(f"{k}={v:.0f}" for k, v in top_t))
            if s["upgrades_pick_n"]:
                picks = ", ".join(
                    f"{k}x{v}" for k, v in s["upgrades_pick"].most_common(15)
                )
                print(
                    f"  upgrades({s['upgrades_pick_n']}, skip={s['upgrades_skip']}): {picks}"
                )
            death = s.get("death")
            if isinstance(death, dict):
                print(
                    f"  death: last={death.get('last_hit_source')} "
                    f"x{death.get('last_hit_amount')} total={death.get('total_damage')} "
                    f"top={death.get('top_sources')}"
                )


def build_json_payload(
    all_runs: List[Dict[str, Any]],
    *,
    dir_path: Path,
    min_events: int,
) -> Dict[str, Any]:
    completed = [s for s in all_runs if s["outcome"] in COMPLETED]
    wins = [s for s in completed if s["outcome"] == "win"]
    dmg_w: Counter = Counter()
    taken: Counter = Counter()
    upgrades: Counter = Counter()
    for s in completed:
        dmg_w.update(s["dmg_dealt_by_weapon"])
        taken.update(s["dmg_taken_by_src"])
        upgrades.update(s["upgrades_pick"])
    return {
        "dir": str(dir_path),
        "total": len(all_runs),
        "meaningful": sum(
            1 for s in all_runs if s["events"] >= min_events or s["outcome"] in COMPLETED
        ),
        "completed": len(completed),
        "winrate": (len(wins) / len(completed)) if completed else None,
        "completed_avg": {
            "night": _avg([s["max_night"] for s in completed]),
            "level": _avg([s["level_end"] for s in completed]),
            "kills": _avg([s["kills_total"] for s in completed]),
            "dmg_out": _avg([s["dmg_dealt_total"] for s in completed]),
            "taken_hits": _avg([s["dmg_taken_hits"] for s in completed]),
            "taken_total": _avg([s["dmg_taken_total"] for s in completed]),
            "duration_s": _avg([s["duration_t"] for s in completed]),
            "upgrades": _avg([s["upgrades_pick_n"] for s in completed]),
        }
        if completed
        else {},
        "weapon_damage": _counter_to_dict(dmg_w),
        "damage_taken_by_source": _counter_to_dict(taken),
        "upgrade_picks": _counter_to_dict(upgrades),
        "runs": [run_to_jsonable(s) for s in all_runs],
    }


def _self_test() -> int:
    """Minimal fixture test for path sandbox + analyze_run aggregation."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        rid = "run_test_win"
        jsonl = root / f"{rid}.jsonl"
        events = [
            {
                "cat": "run",
                "night": 0,
                "t": 0,
                "data": {
                    "action": "start",
                    "bot": True,
                    "character": "watcher",
                    "max_hp": 100,
                    "seed": 42,
                    "started_at": "2026-01-01 00:00:00",
                },
            },
            {
                "cat": "damage",
                "night": 1,
                "t": 1.0,
                "data": {
                    "action": "dealt_agg",
                    "total": 100,
                    "by_weapon": [{"id": "harpoon", "dealt": 100, "hits": 5}],
                },
            },
            {
                "cat": "damage",
                "night": 1,
                "t": 1.1,
                "data": {"action": "taken", "amount": 7, "source": "enemy_projectile"},
            },
            {
                "cat": "upgrade",
                "night": 1,
                "t": 2.0,
                "data": {"action": "pick", "id": "heal"},
            },
            {
                "cat": "monster",
                "night": 1,
                "t": 3.0,
                "data": {"action": "death_agg", "killed_total": 12},
            },
            {
                "cat": "character",
                "night": 1,
                "t": 4.0,
                "data": {
                    "action": "snapshot",
                    "level": 3,
                    "hp": 90,
                    "max_hp": 100,
                    "phase": "night_start",
                },
            },
            {
                "cat": "run",
                "night": 5,
                "t": 50.0,
                "data": {"action": "end", "outcome": "win", "level": 5},
            },
        ]
        jsonl.write_text(
            "\n".join(json.dumps(e, ensure_ascii=False) for e in events) + "\n",
            encoding="utf-8",
        )
        (root / "index.json").write_text(
            json.dumps(
                {
                    "version": 1,
                    "runs": [
                        {
                            "id": rid,
                            "path": f"user://combat_logs/{rid}.jsonl",
                            "outcome": "win",
                        },
                        {
                            "id": "evil",
                            "path": str(Path(tmp).resolve().parent / "outside.jsonl"),
                            "outcome": "win",
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )

        assert resolve_run_path(root, {"id": rid, "path": f"user://combat_logs/{rid}.jsonl"})
        assert resolve_run_path(root, {"id": "evil", "path": str(Path.cwd() / "README.md")}) is None

        sm = analyze_run({"id": rid, "outcome": "win"}, jsonl)
        assert sm["outcome"] == "win"
        assert sm["level_end"] == 5
        assert sm["final_char"].get("level") == 3
        assert sm["dmg_dealt_by_weapon"]["harpoon"] == 100
        assert sm["dmg_taken_by_src"]["enemy_projectile"] == 7
        assert sm["kills_total"] == 12
        assert sm["upgrades_pick"]["heal"] == 1

        filtered = filter_runs(
            [
                {"outcome": "win", "events": 10},
                {"outcome": "aborted", "events": 2},
                {"outcome": "death", "events": 200},
            ],
            completed_only=True,
        )
        assert [r["outcome"] for r in filtered] == ["win", "death"]

        # Filtered-empty index must NOT glob all files
        other = root / "run_other.jsonl"
        other.write_text("{}\n", encoding="utf-8")
        assert collect_runs(root, [], fallback_glob=False) == []
        globbed = collect_runs(root, [], fallback_glob=True)
        assert len(globbed) >= 2

    print("self-test OK")
    return 0



def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass

    ap = argparse.ArgumentParser(description="Aggregate Tidekeeper CombatLog JSONL stats")
    ap.add_argument("--dir", type=str, default="", help="combat_logs directory")
    ap.add_argument("--latest", type=int, default=0, help="only latest N index entries (0=all)")
    ap.add_argument("--run", type=str, default="", help="filter by run id substring")
    ap.add_argument(
        "--min-events",
        type=int,
        default=100,
        help="meaningful-run threshold for --detail focus (default 100)",
    )
    ap.add_argument(
        "--completed-only",
        action="store_true",
        help="only include win/death runs (table, aggregates, detail, json)",
    )
    ap.add_argument("--detail", action="store_true", help="print per-run build/death details")
    ap.add_argument("--top", type=int, default=10, help="top-N lists (default 10)")
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    ap.add_argument("--self-test", action="store_true", help="run built-in fixture checks")
    args = ap.parse_args()

    if args.self_test:
        return _self_test()

    dir_path = Path(args.dir) if args.dir else default_log_dir()
    if not dir_path.is_dir():
        print(f"No combat log dir: {dir_path}", file=sys.stderr)
        print("Play a non-headless run (debug.bat) first.", file=sys.stderr)
        return 1

    index = load_index(dir_path)
    raw_index_runs: List[Dict[str, Any]] = list(index.get("runs") or [])
    index_runs = list(raw_index_runs)
    if args.run:
        needle = args.run.lower()
        index_runs = [r for r in index_runs if needle in str(r.get("id", "")).lower()]
    if args.latest > 0 and len(index_runs) > args.latest:
        index_runs = index_runs[-args.latest :]

    # Only glob when there was never an index listing (and user did not filter).
    fallback_glob = (not raw_index_runs) and (not args.run)
    all_runs = collect_runs(dir_path, index_runs, fallback_glob=fallback_glob)
    all_runs = filter_runs(all_runs, completed_only=args.completed_only)
    if not all_runs:
        reason = ""
        if args.run or args.completed_only or (raw_index_runs and not index_runs):
            reason = " (after filters)"
        print(f"No runs in {dir_path}{reason}")
        return 0


    if args.json:
        payload = build_json_payload(all_runs, dir_path=dir_path, min_events=args.min_events)
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    print_report(
        all_runs,
        dir_path=dir_path,
        min_events=args.min_events,
        detail=args.detail,
        top=max(1, args.top),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
