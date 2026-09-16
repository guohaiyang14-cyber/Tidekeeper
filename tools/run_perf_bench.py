#!/usr/bin/env python3
# ============================================================================
# run_perf_bench.py — 跑 R1 350 敌帧时/内存压测并汇总 [PERF] 行
#
# 用法：
#   python tools/run_perf_bench.py
#   python tools/run_perf_bench.py --headless-only
#   python tools/run_perf_bench.py --godot "E:\\Godot\\Godot_v4.7.1-stable_win64_console.exe"
#   python tools/run_perf_bench.py --json
#
# 注意：勿加 --fixed-fps（会锁死墙钟，无法估 fps）。
# headless 跳过完整渲染，A1 结论为 CPU/逻辑代理；窗口模式更接近 Profiler。
# ============================================================================
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "godot_project"
SCENE = "res://scenes/tests/r1_perf_bench.tscn"
RE_PERF = re.compile(r"^\[PERF\]\s+(.+)$")
RE_KV = re.compile(r"(\w+)=([^\s]+)")

DEFAULT_GODOT_CANDIDATES = [
    os.environ.get("GODOT_BIN", ""),
    r"E:\Godot\Godot_v4.7.1-stable_win64_console.exe",
    r"C:\Godot\Godot_v4.7.1-stable_win64_console.exe",
]


def find_godot(explicit: Optional[str]) -> Path:
    if explicit:
        p = Path(explicit)
        if not p.is_file():
            raise SystemExit(f"Godot not found: {p}")
        return p
    local = ROOT / "debug.local.bat"
    if local.is_file():
        text = local.read_text(encoding="utf-8", errors="ignore")
        m = re.search(r'GODOT_BIN=(.+)', text)
        if m:
            cand = Path(m.group(1).strip().strip('"'))
            if cand.is_file():
                return cand
    for raw in DEFAULT_GODOT_CANDIDATES:
        if not raw:
            continue
        p = Path(raw)
        if p.is_file():
            return p
    raise SystemExit(
        "Godot 4.7.1 not found. Set GODOT_BIN or pass --godot, "
        "or create debug.local.bat (see debug.local.bat.example)."
    )


def parse_perf_lines(text: str) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    for line in text.splitlines():
        m = RE_PERF.match(line.strip())
        if not m:
            continue
        row = {k: v for k, v in RE_KV.findall(m.group(1))}
        if row:
            rows.append(row)
    return rows


def run_mode(godot: Path, headless: bool, timeout: int) -> Dict:
    cmd = [str(godot)]
    if headless:
        cmd.append("--headless")
    # 明确不要 --fixed-fps
    cmd.extend(["--path", str(PROJECT), SCENE])
    print(f"[run] {' '.join(cmd)}", flush=True)
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            cwd=str(ROOT),
        )
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or "") + "\n" + (exc.stderr or "")
        return {
            "mode": "headless" if headless else "windowed",
            "ok": False,
            "exit_code": -1,
            "error": f"timeout after {timeout}s",
            "perf": parse_perf_lines(out),
            "tail": out[-2000:],
        }
    out = (proc.stdout or "") + "\n" + (proc.stderr or "")
    perf = parse_perf_lines(out)
    summary = next((r for r in perf if r.get("event") == "summary"), None)
    return {
        "mode": "headless" if headless else "windowed",
        "ok": proc.returncode == 0,
        "exit_code": proc.returncode,
        "perf": perf,
        "summary": summary,
        "tail": "\n".join(out.splitlines()[-40:]),
    }


def _bool(s: Optional[str]) -> Optional[bool]:
    if s is None:
        return None
    return s.lower() == "true"


def print_report(results: List[Dict]) -> int:
    overall_fail = 0
    print("=" * 60)
    print("R1 Perf Bench summary (A1 frame proxy / A4 memory proxy)")
    print("=" * 60)
    for r in results:
        print(f"\n--- mode={r['mode']} exit={r['exit_code']} ok={r['ok']} ---")
        # 非零 exit（刷不满等 assert）与 A1/A4 失败均计入失败，不可被 summary 盖住
        if r.get("error") or not r.get("ok"):
            overall_fail = 1
            if r.get("error"):
                print(f"  error: {r['error']}")
        s = r.get("summary") or {}
        if s:
            a1 = _bool(s.get("a1_pass"))
            a4 = _bool(s.get("a4_pass"))
            print(
                f"  A1={a1} A4={a4} worst_wall_ms={s.get('worst_avg_ms')} "
                f"wall_fps~={s.get('wall_fps_proxy')} process_p95={s.get('worst_p95_ms')} "
                f"mem_delta={s.get('mem_delta')} note={s.get('note')}"
            )
            if a1 is False or a4 is False:
                overall_fail = 1
            if _bool(s.get("fill_ok")) is False:
                overall_fail = 1
                print("  fill_ok=false (spawn cap not met)")
        else:
            print("  (no [PERF] summary; see tail)")
            print(r.get("tail", "")[-1500:])
        for row in r.get("perf") or []:
            if row.get("event") == "cycle":
                print(
                    f"  cycle {row.get('cycle')}: wall_avg={row.get('wall_avg_ms')}ms "
                    f"wall_fps={row.get('wall_fps')} proc_p95={row.get('p95_ms')} "
                    f"mem={row.get('static_bytes')}"
                )
    print("\nNote: headless skips full render; final A1 still wants editor Profiler.")
    print("A1 proxy FAIL -> start B1 MultiMesh; PASS -> optional human Profiler check.")
    return overall_fail


def main() -> int:
    ap = argparse.ArgumentParser(description="Run Tidekeeper R1 350-enemy perf bench")
    ap.add_argument("--godot", default=None, help="Godot 4.7.1 可执行路径")
    ap.add_argument("--headless-only", action="store_true", help="只跑 headless")
    ap.add_argument("--windowed-only", action="store_true", help="只跑窗口模式")
    ap.add_argument("--timeout", type=int, default=180, help="单模式超时秒数")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    args = ap.parse_args()

    godot = find_godot(args.godot)
    modes: List[bool] = []
    if args.windowed_only:
        modes = [False]
    elif args.headless_only:
        modes = [True]
    else:
        modes = [True, False]

    results = [run_mode(godot, headless=h, timeout=args.timeout) for h in modes]
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
        fail = any(not r.get("ok") for r in results)
        for r in results:
            s = r.get("summary") or {}
            if (
                _bool(s.get("a1_pass")) is False
                or _bool(s.get("a4_pass")) is False
                or _bool(s.get("fill_ok")) is False
            ):
                fail = True
        return 1 if fail else 0
    return print_report(results)


if __name__ == "__main__":
    sys.exit(main())
