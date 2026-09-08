#!/usr/bin/env python3
# ============================================================================
# check_bot_acceptance.py — 从 Godot 日志汇总 TestBot ACCEPT / 对照验收清单
#
# 用法：
#   python tools/check_bot_acceptance.py
#   python tools/check_bot_acceptance.py --latest
#   python tools/check_bot_acceptance.py --all-logs
#   python tools/check_bot_acceptance.py --suite acceptance
#   python tools/check_bot_acceptance.py --json
#   python tools/check_bot_acceptance.py --self-test
# ============================================================================
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

APP_NAME = "Tidekeeper"

RE_ACCEPT = re.compile(
    r"\[TestBot\]\s*ACCEPT\s+id=(\S+)\s+status=(\S+)(?:\s+detail=(\S+))?"
)
RE_SUMMARY = re.compile(r"\[TestBot\]\s*ACCEPT_SUMMARY\s+(.+)$")
RE_SUITE = re.compile(r"\[TestBot\]\s*验收套件\s+suite=(\S+)")
RE_KV = re.compile(r"(\w+)=([^\s]+)")

# 清单 id → 简述（与 docs/TestBot验收任务.md / 原型验证验收清单 对齐）
CHECKLIST_LABELS: Dict[str, str] = {
    "1.1.1": "昼夜循环≥10夜",
    "1.1.2": "夜长45/60/90/120",
    "1.2.1": "移速数据驱动",
    "1.2.3": "角色可开局",
    "2.4.2": "词缀/荆棘校准",
    "2.4.3": "词缀夜间规则",
    "3.3": "可玩到8~10夜",
    "4.3.12": "属性软上限",
    "4.5.4": "宝箱开箱奖励",
    "4.9.1": "同屏敌人峰值",
    "5.2": "连续3局无崩溃(≥N8)",
    "4.5.2": "N15排除潮汐反转",
    "4.5.3": "夹击规则",
    "4.2.8": "精炼入口",
    "2.5.3": "终局通关",
    "4.10.1": "全流程代理",
    "4.6.1": "角色数据驱动",
    "4.6.3": "开局武器映射",
    "4.6.5": "角色特性",
    "4.8.1": "难度档位",
}


def default_log_dir() -> Path:
    if sys.platform.startswith("win"):
        base = os.environ.get("APPDATA", "")
        return Path(base) / "Godot" / "app_userdata" / APP_NAME / "logs"
    home = Path.home()
    return home / ".local" / "share" / "godot" / "app_userdata" / APP_NAME / "logs"


def list_log_files(log_dir: Path, all_logs: bool) -> List[Path]:
    if not log_dir.is_dir():
        return []
    primary = log_dir / "godot.log"
    if not all_logs:
        return [primary] if primary.is_file() else []
    files = sorted(log_dir.glob("godot*.log"), key=lambda p: p.stat().st_mtime)
    return files


def _should_apply_status(prev: str, status: str) -> bool:
    """与 TestBot._record_accept 对齐：fail/pass 可互相覆盖；skip/info 不覆盖 pass/fail。"""
    if status not in ("pass", "fail", "skip", "info"):
        return False
    if prev == "":
        return True
    if status in ("fail", "pass"):
        return True
    # skip/info：不覆盖 pass/fail
    return prev not in ("pass", "fail")


def _apply_accept(
    accepts: Dict[str, str],
    details: Dict[str, str],
    cid: str,
    status: str,
    detail: str = "",
) -> None:
    prev = accepts.get(cid, "")
    if not _should_apply_status(prev, status):
        return
    accepts[cid] = status
    if detail:
        details[cid] = detail


def parse_text(text: str) -> Dict[str, object]:
    accepts: Dict[str, str] = {}
    details: Dict[str, str] = {}
    summaries: List[Dict[str, str]] = []
    suite = ""
    for line in text.splitlines():
        m_s = RE_SUITE.search(line)
        if m_s:
            suite = m_s.group(1)
        m = RE_ACCEPT.search(line)
        if m:
            cid, status, detail = m.group(1), m.group(2), m.group(3) or ""
            _apply_accept(accepts, details, cid, status, detail)
            continue
        m2 = RE_SUMMARY.search(line)
        if m2:
            kv = {mm.group(1): mm.group(2) for mm in RE_KV.finditer(m2.group(1))}
            summaries.append(kv)
            if kv.get("suite") and kv["suite"] != "-":
                suite = kv["suite"]
    return {
        "suite": suite,
        "accepts": accepts,
        "details": details,
        "summaries": summaries,
    }


def merge_results(parts: Iterable[Dict[str, object]]) -> Dict[str, object]:
    accepts: Dict[str, str] = {}
    details: Dict[str, str] = {}
    summaries: List[Dict[str, str]] = []
    suite = ""
    for part in parts:
        suite = str(part.get("suite") or suite)
        part_details: Dict[str, str] = part.get("details") or {}  # type: ignore[assignment]
        for cid, st in (part.get("accepts") or {}).items():  # type: ignore[union-attr]
            _apply_accept(accepts, details, str(cid), str(st), str(part_details.get(cid, "")))
        summaries.extend(part.get("summaries") or [])  # type: ignore[arg-type]
    return {"suite": suite, "accepts": accepts, "details": details, "summaries": summaries}


def format_report(data: Dict[str, object], filter_suite: str = "") -> str:
    lines: List[str] = []
    suite = str(data.get("suite") or "-")
    if filter_suite and suite not in ("-", filter_suite):
        lines.append(f"(日志 suite={suite}，筛选={filter_suite} — 仍展示全部 ACCEPT)")
    lines.append(f"suite: {suite}")
    accepts: Dict[str, str] = data.get("accepts") or {}  # type: ignore[assignment]
    details: Dict[str, str] = data.get("details") or {}  # type: ignore[assignment]
    if not accepts:
        lines.append("未找到 [TestBot] ACCEPT 行。请用 debug.bat --bot-suite=… 跑局后再查。")
        return "\n".join(lines)
    by_status: Dict[str, List[str]] = defaultdict(list)
    for cid, st in sorted(accepts.items()):
        by_status[st].append(cid)
    for st in ("pass", "fail", "skip", "info"):
        ids = by_status.get(st, [])
        if not ids:
            continue
        lines.append(f"\n## {st} ({len(ids)})")
        for cid in ids:
            label = CHECKLIST_LABELS.get(cid, "")
            det = details.get(cid, "")
            extra = f"  {label}" if label else ""
            dstr = f"  detail={det}" if det else ""
            lines.append(f"  {cid}{extra}{dstr}")
    summaries = data.get("summaries") or []
    if summaries:
        lines.append("\n## ACCEPT_SUMMARY (latest)")
        last = summaries[-1]
        lines.append("  " + " ".join(f"{k}={v}" for k, v in last.items()))
    return "\n".join(lines)


def self_test() -> int:
    sample = (
        "[TestBot] 验收套件 suite=smoke character=watcher\n"
        "[TestBot] ACCEPT id=1.1.2 status=pass detail=n=1_expect=45_got=45\n"
        "[TestBot] ACCEPT id=5.2 status=fail detail=runs_ge8=1\n"
        "[TestBot] ACCEPT id=5.2 status=pass detail=runs_ge8=3_script_err=0\n"
        "[TestBot] ACCEPT id=5.2 status=fail detail=reconcile_runs_ge8=3_script_err=1\n"
        "[TestBot] ACCEPT id=4.2.8 status=skip detail=no_refine\n"
        "[TestBot] ACCEPT id=4.2.8 status=pass detail=refine=harpoon\n"
        "[TestBot] ACCEPT_SUMMARY suite=smoke runs=3 wins=0 ge8=3 ge10=2 script_err=1 pass=1.1.2,4.2.8 fail=5.2 skip=-\n"
    )
    data = parse_text(sample)
    assert data["suite"] == "smoke"
    assert data["accepts"]["5.2"] == "fail", data["accepts"]
    assert data["accepts"]["1.1.2"] == "pass"
    assert data["accepts"]["4.2.8"] == "pass"
    assert data["details"]["5.2"].startswith("reconcile")
    assert len(data["summaries"]) == 1
    merged = merge_results(
        [
            {"suite": "a", "accepts": {"5.2": "pass"}, "details": {"5.2": "ok"}, "summaries": []},
            {"suite": "a", "accepts": {"5.2": "fail"}, "details": {"5.2": "err"}, "summaries": []},
        ]
    )
    assert merged["accepts"]["5.2"] == "fail"
    assert merged["details"]["5.2"] == "err"
    print("self-test OK")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="汇总 TestBot ACCEPT 对照验收清单")
    ap.add_argument("--dir", type=Path, default=None, help="日志目录")
    ap.add_argument("--log", type=Path, default=None, help="指定单个日志文件")
    ap.add_argument("--all-logs", action="store_true", help="合并全部 godot*.log")
    ap.add_argument("--latest", action="store_true", help="同默认（仅 godot.log）")
    ap.add_argument("--suite", default="", help="仅标注期望套件名")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    if args.log:
        files = [args.log]
    else:
        log_dir = args.dir or default_log_dir()
        files = list_log_files(log_dir, args.all_logs or False)
        if not files:
            print(f"未找到日志：{log_dir}", file=sys.stderr)
            return 1

    parts = []
    for f in files:
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            print(f"读失败 {f}: {exc}", file=sys.stderr)
            continue
        parts.append(parse_text(text))
    data = merge_results(parts)
    data["files"] = [str(f) for f in files]

    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(f"日志文件 ({len(files)}):")
        for f in files:
            print(f"  - {f}")
        print()
        print(format_report(data, filter_suite=args.suite.strip()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
