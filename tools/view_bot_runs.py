#!/usr/bin/env python3
# ============================================================================
# view_bot_runs.py — 从 Godot 日志解析 TestBot 自动试玩局次
#
# 默认只读最新 godot.log（避免轮转切片把同一局算成多次「进行中」）。
# 以「出现 [TestBot] 行」区分机器人局与 headless 单测。
#
# 用法：
#   python tools/view_bot_runs.py
#   python tools/view_bot_runs.py --latest 10 --detail
#   python tools/view_bot_runs.py --all-logs
#   python tools/view_bot_runs.py --log path/to/godot.log
#   python tools/view_bot_runs.py --json
#   python tools/view_bot_runs.py --self-test
#   view_bot_runs.bat --latest 5 --detail
# ============================================================================
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterable, List, Optional, Sequence, Tuple


APP_NAME = "Tidekeeper"

RE_ENGINE = re.compile(r"^Godot Engine v", re.M)
RE_BOT_LINE = re.compile(r"\[TestBot\]")
RE_RUN_START = re.compile(
    r"\[GameState\]\s*新局开始:\s*character=(\S+)\s+seed=(-?\d+)\s+max_hp=(\d+)"
)
RE_ENTER_NIGHT = re.compile(r"\[GameState\]\s*进入第\s*(\d+)\s*夜")
RE_WORLD_NIGHT = re.compile(r"\[World\]\s*→\s*夜晚阶段\s*\(第\s*(\d+)\s*夜\)")
RE_WORLD_OVER = re.compile(r"\[World\]\s*游戏结束:\s*(\S+)")
RE_GS_OVER = re.compile(r"\[GameState\]\s*游戏结束:\s*(\S+)\s*\(已存活\s*(\d+)\s*夜\)")
RE_WIN = re.compile(r"\[World\]\s*通关")
RE_BOT_BUY = re.compile(r"\[TestBot\]\s*购买\s+(.+)$")
RE_BOT_FUSE = re.compile(r"\[TestBot\]\s*融合武器\s+(\S+)")
RE_BOT_REFINE = re.compile(r"\[TestBot\]\s*精炼武器\s+(\S+)")
RE_BOT_SKIP = re.compile(r"\[TestBot\]\s*跳过抉择之昼")
RE_SCRIPT_ERR = re.compile(r"SCRIPT ERROR|Error at:", re.I)

_OUTCOME_RANK = {"win": 3, "death": 3, "aborted": 2, "in_progress": 1}


@dataclass
class BotRun:
    source: str
    character: str
    seed: int
    max_hp: int
    max_night: int = 0
    outcome: str = "in_progress"  # in_progress | death | win | aborted
    reason: str = ""
    buys: List[str] = field(default_factory=list)
    fuses: List[str] = field(default_factory=list)
    refines: List[str] = field(default_factory=list)
    day_skips: int = 0
    script_errors: int = 0
    bot_touched: bool = False  # 本局出现过 [TestBot] 行，或启用后开启

    @property
    def label(self) -> str:
        if self.outcome == "win":
            return "通关"
        if self.outcome == "death":
            return f"死亡:{self.reason or '?'}"
        if self.outcome == "aborted":
            return "中断"
        return "进行中"


def default_log_dirs() -> List[Path]:
    dirs: List[Path] = []
    appdata = os.environ.get("APPDATA")
    if appdata:
        dirs.append(Path(appdata) / "Godot" / "app_userdata" / APP_NAME / "logs")
    home = Path.home()
    dirs.append(home / ".local" / "share" / "godot" / "app_userdata" / APP_NAME / "logs")
    dirs.append(
        home
        / "Library"
        / "Application Support"
        / "Godot"
        / "app_userdata"
        / APP_NAME
        / "logs"
    )
    return dirs


def _unique_sorted(paths: Iterable[Path]) -> List[Path]:
    found: List[Path] = []
    seen = set()
    for p in paths:
        try:
            key = p.resolve()
        except OSError:
            key = p
        if key in seen or not p.is_file():
            continue
        seen.add(key)
        found.append(p)
    found.sort(key=lambda p: p.stat().st_mtime)
    return found


def list_userdata_logs() -> List[Path]:
    candidates: List[Path] = []
    for d in default_log_dirs():
        if d.is_dir():
            candidates.extend(d.glob("godot*.log"))
    return _unique_sorted(candidates)


def pick_default_logs(all_logs: bool) -> List[Path]:
    """默认只取当前 godot.log（或 mtime 最新一份）；--all-logs 取全部。"""
    found = list_userdata_logs()
    if not found:
        return []
    if all_logs:
        return found
    for p in reversed(found):
        if p.name.lower() == "godot.log":
            return [p]
    return [found[-1]]


def resolve_log_args(log_args: Sequence[str], all_logs: bool) -> List[Path]:
    if not log_args:
        return pick_default_logs(all_logs)
    paths: List[Path] = []
    for raw in log_args:
        p = Path(raw)
        if p.is_dir():
            paths.extend(p.glob("godot*.log"))
        elif p.is_file():
            paths.append(p)
        else:
            print(f"[warn] 不存在: {p}", file=sys.stderr)
    paths = _unique_sorted(paths)
    if all_logs or len(paths) <= 1:
        return paths
    # 显式多文件且未要求 all-logs：仍全部使用，但后续会 dedupe
    return paths


def read_text(path: Path) -> str:
    raw = path.read_bytes().replace(b"\x00", b"")
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    return raw.decode("utf-8", errors="replace")


def split_sessions(text: str) -> List[str]:
    spans = list(RE_ENGINE.finditer(text))
    if not spans:
        return [text] if text.strip() else []
    sessions: List[str] = []
    for i, m in enumerate(spans):
        end = spans[i + 1].start() if i + 1 < len(spans) else len(text)
        sessions.append(text[m.start() : end])
    return sessions


def _close_run(run: Optional[BotRun], outcome: str, reason: str = "", night: Optional[int] = None) -> None:
    if run is None:
        return
    if night is not None and night > run.max_night:
        run.max_night = night
    run.outcome = outcome
    if reason:
        run.reason = reason


def parse_bot_session(text: str, source: str) -> List[BotRun]:
    """解析一个 Godot 进程会话。单测与 Bot 可能同文件；只保留 bot_touched 局。"""
    if "[TestBot]" not in text:
        return []
    runs: List[BotRun] = []
    current: Optional[BotRun] = None
    bot_active = False  # 见过任意 [TestBot] 后，后续新局都算 bot 局

    for line in text.splitlines():
        line = line.rstrip("\r")

        if RE_BOT_LINE.search(line):
            bot_active = True
            if current is not None:
                current.bot_touched = True

        if RE_SCRIPT_ERR.search(line) and current is not None and current.bot_touched:
            current.script_errors += 1

        m = RE_RUN_START.search(line)
        if m:
            if current is not None and current.outcome == "in_progress":
                current.outcome = "aborted"
                current.reason = current.reason or "interrupted"
            current = BotRun(
                source=source,
                character=m.group(1),
                seed=int(m.group(2)),
                max_hp=int(m.group(3)),
                bot_touched=bot_active,
            )
            runs.append(current)
            continue

        if current is None:
            continue

        m = RE_ENTER_NIGHT.search(line) or RE_WORLD_NIGHT.search(line)
        if m:
            night = int(m.group(1))
            if night > current.max_night:
                current.max_night = night
            continue

        m = RE_GS_OVER.search(line)
        if m:
            _close_run(current, "death", m.group(1), int(m.group(2)))
            continue

        m = RE_WORLD_OVER.search(line)
        if m:
            if current.outcome == "in_progress":
                _close_run(current, "death", m.group(1))
            continue

        if RE_WIN.search(line):
            _close_run(current, "win", "clear", 20)
            continue

        m = RE_BOT_BUY.search(line)
        if m:
            current.bot_touched = True
            current.buys.append(m.group(1).strip())
            continue
        m = RE_BOT_FUSE.search(line)
        if m:
            current.bot_touched = True
            current.fuses.append(m.group(1))
            continue
        m = RE_BOT_REFINE.search(line)
        if m:
            current.bot_touched = True
            current.refines.append(m.group(1))
            continue
        if RE_BOT_SKIP.search(line):
            current.bot_touched = True
            current.day_skips += 1
            continue

    return [r for r in runs if r.bot_touched]


def parse_files(paths: Iterable[Path]) -> List[BotRun]:
    all_runs: List[BotRun] = []
    for path in paths:
        try:
            text = read_text(path)
        except OSError as exc:
            print(f"[warn] 无法读取 {path}: {exc}", file=sys.stderr)
            continue
        sessions = split_sessions(text)
        for i, session in enumerate(sessions):
            src = str(path) if len(sessions) == 1 else f"{path.name}#s{i}"
            all_runs.extend(parse_bot_session(session, src))
    return all_runs


def _run_sort_key(index_and_run: Tuple[int, BotRun]) -> Tuple[int, int, int]:
    i, r = index_and_run
    return (_OUTCOME_RANK.get(r.outcome, 0), r.max_night, i)


def dedupe_runs(runs: List[BotRun]) -> List[BotRun]:
    """合并跨日志轮转的同一局：同角色+种子时，丢掉被截断的进行中/中断，保留完结局。"""
    groups: dict[Tuple[str, int], List[Tuple[int, BotRun]]] = defaultdict(list)
    for i, r in enumerate(runs):
        groups[(r.character, r.seed)].append((i, r))

    drop: set[int] = set()
    for items in groups.values():
        if len(items) < 2:
            continue
        finished = [(i, r) for i, r in items if r.outcome in ("death", "win")]
        stubs = [(i, r) for i, r in items if r.outcome in ("in_progress", "aborted")]
        if finished and stubs:
            for i, _ in stubs:
                drop.add(i)
            continue
        if not finished and len(stubs) > 1:
            best_i, _ = max(stubs, key=_run_sort_key)
            for i, _ in stubs:
                if i != best_i:
                    drop.add(i)

    return [r for i, r in enumerate(runs) if i not in drop]


def summarize(runs: List[BotRun]) -> dict:
    finished = [r for r in runs if r.outcome in ("death", "win")]
    deaths = [r for r in finished if r.outcome == "death"]
    wins = [r for r in finished if r.outcome == "win"]
    night_hist = Counter(r.max_night for r in finished)
    death_nights = Counter(r.max_night for r in deaths)
    reasons = Counter(r.reason for r in deaths)
    return {
        "total_runs": len(runs),
        "finished": len(finished),
        "in_progress": sum(1 for r in runs if r.outcome == "in_progress"),
        "aborted": sum(1 for r in runs if r.outcome == "aborted"),
        "wins": len(wins),
        "deaths": len(deaths),
        "avg_night_finished": (
            round(sum(r.max_night for r in finished) / len(finished), 2) if finished else 0.0
        ),
        "best_night": max((r.max_night for r in runs), default=0),
        "night_histogram": dict(sorted(night_hist.items())),
        "death_night_histogram": dict(sorted(death_nights.items())),
        "death_reasons": dict(reasons.most_common()),
        "unique_seeds": len({r.seed for r in runs}),
    }


def print_table(runs: List[BotRun], detail: bool) -> None:
    if not runs:
        print("未找到 TestBot 局次（日志中需有 [TestBot] 行动行）。")
        return
    header = f"{'#':>4}  {'角色':<10} {'种子':>20}  {'夜':>3}  {'结果':<16}  {'购':>3}  {'源'}"
    print(header)
    print("-" * max(len(header), 72))
    for i, r in enumerate(runs, 1):
        src = Path(r.source.split("#")[0]).name
        if "#" in r.source:
            src = r.source
        print(
            f"{i:4d}  {r.character:<10} {r.seed:20d}  {r.max_night:3d}  "
            f"{r.label:<16}  {len(r.buys):3d}  {src}"
        )
        if detail:
            if r.buys:
                print(f"       购买: {', '.join(r.buys)}")
            if r.fuses:
                print(f"       融合: {', '.join(r.fuses)}")
            if r.refines:
                print(f"       精炼: {', '.join(r.refines)}")
            if r.day_skips:
                print(f"       跳过昼: {r.day_skips}")
            if r.script_errors:
                print(f"       SCRIPT ERROR 行: {r.script_errors}")


def print_summary(stats: dict) -> None:
    print()
    print("=== 汇总 ===")
    print(
        f"局次 {stats['total_runs']}  |  完成 {stats['finished']}  |  "
        f"进行中 {stats['in_progress']}  |  中断 {stats['aborted']}"
    )
    print(
        f"通关 {stats['wins']}  |  死亡 {stats['deaths']}  |  "
        f"完成局均夜 {stats['avg_night_finished']}  |  最高夜 {stats['best_night']}  |  "
        f"不同种子 {stats['unique_seeds']}"
    )
    if stats["death_night_histogram"]:
        parts = [f"N{n}×{c}" for n, c in stats["death_night_histogram"].items()]
        print("死亡夜分布: " + "  ".join(parts))
    if stats["death_reasons"]:
        parts = [f"{k}×{v}" for k, v in stats["death_reasons"].items()]
        print("死因: " + "  ".join(parts))


def configure_stdio() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
        except Exception:
            pass


def run_self_test() -> int:
    failures: List[str] = []

    def check(name: str, cond: bool) -> None:
        if not cond:
            failures.append(name)

    unit = (
        "Godot Engine v4.7.1\n"
        "[GameState] 新局开始: character=watcher seed=1 max_hp=100\n"
        "[GameState] 进入第 1 夜\n"
        "[GameState] 游戏结束: hp_zero (已存活 0 夜)\n"
    )
    check("unit_filtered", parse_bot_session(unit, "u") == [])

    death = (
        "[TestBot] 已启用\n"
        "[GameState] 新局开始: character=watcher seed=42 max_hp=100\n"
        "[GameState] 进入第 5 夜\n"
        "[TestBot] 购买 铁链\n"
        "[TestBot] 跳过抉择之昼 → 下一夜\n"
        "[World] 游戏结束: hp_zero\n"
        "[GameState] 游戏结束: hp_zero (已存活 5 夜)\n"
    )
    d_runs = parse_bot_session(death, "d")
    check("death_count", len(d_runs) == 1)
    check("death_night", d_runs[0].max_night == 5 and d_runs[0].outcome == "death")
    check("death_buy", d_runs[0].buys == ["铁链"] and d_runs[0].day_skips == 1)

    win = "[TestBot] x\n[GameState] 新局开始: character=a seed=1 max_hp=1\n[World] 通关！\n"
    w = parse_bot_session(win, "w")[0]
    check("win", w.outcome == "win" and w.max_night == 20)

    aborted = (
        "[TestBot] x\n"
        "[GameState] 新局开始: character=a seed=1 max_hp=1\n"
        "[GameState] 进入第 3 夜\n"
        "[GameState] 新局开始: character=a seed=2 max_hp=1\n"
    )
    a_runs = parse_bot_session(aborted, "a")
    check("aborted", a_runs[0].outcome == "aborted" and a_runs[0].max_night == 3)
    check("aborted_next", a_runs[1].seed == 2 and a_runs[1].outcome == "in_progress")

    stub = BotRun("old.log", "watcher", 20260824, 100, max_night=3, outcome="in_progress", bot_touched=True)
    done = BotRun("godot.log", "watcher", 20260824, 100, max_night=5, outcome="death", reason="hp_zero", bot_touched=True)
    other = BotRun("godot.log", "watcher", 99, 100, max_night=2, outcome="in_progress", bot_touched=True)
    merged = dedupe_runs([stub, done, other])
    check("dedupe_drop_stub", len(merged) == 2 and merged[0].outcome == "death" and merged[1].seed == 99)

    stubs = [
        BotRun("a.log", "watcher", 7, 100, max_night=2, outcome="in_progress", bot_touched=True),
        BotRun("b.log", "watcher", 7, 100, max_night=4, outcome="in_progress", bot_touched=True),
    ]
    best = dedupe_runs(stubs)
    check("dedupe_best_stub", len(best) == 1 and best[0].max_night == 4)

    if failures:
        print("SELF-TEST FAIL:", ", ".join(failures))
        return 1
    print("SELF-TEST OK (8 checks)")
    return 0


def main() -> int:
    configure_stdio()
    ap = argparse.ArgumentParser(description="查看 TestBot 自动试玩局次记录（解析 Godot 日志）")
    ap.add_argument(
        "--log",
        action="append",
        default=[],
        metavar="PATH",
        help="指定日志文件或目录（目录仅匹配 godot*.log）；可多次",
    )
    ap.add_argument(
        "--all-logs",
        action="store_true",
        help="读取 userdata 下全部 godot*.log（默认只读当前 godot.log）并去重轮转截断局",
    )
    ap.add_argument("--latest", type=int, default=0, metavar="N", help="只显示最近 N 局（0=全部）")
    ap.add_argument("--detail", action="store_true", help="展开购买/融合/精炼")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    ap.add_argument("--self-test", action="store_true", help="跑内置解析回归后退出")
    args = ap.parse_args()

    if args.self_test:
        return run_self_test()

    paths = resolve_log_args(args.log, args.all_logs)
    if not paths:
        print("未找到日志。可显式传入：python tools/view_bot_runs.py --log <godot.log>", file=sys.stderr)
        print("默认目录：", file=sys.stderr)
        for d in default_log_dirs():
            print(f"  {d}", file=sys.stderr)
        return 1

    runs = parse_files(paths)
    if args.all_logs or len(paths) > 1:
        runs = dedupe_runs(runs)

    if args.latest > 0:
        runs = runs[-args.latest :]

    stats = summarize(runs)
    if args.json:
        payload = {"summary": stats, "runs": [asdict(r) for r in runs], "logs": [str(p) for p in paths]}
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    print(f"日志文件 ({len(paths)}):")
    for p in paths:
        print(f"  - {p}")
    print()
    print_table(runs, args.detail)
    print_summary(stats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
