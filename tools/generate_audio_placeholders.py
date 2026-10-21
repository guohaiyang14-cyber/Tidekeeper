#!/usr/bin/env python3
# ============================================================================
# generate_audio_placeholders.py — 生成 Tidekeeper 占位音频（纯合成，零外部依赖）
#
# 输出：godot_project/assets/audio/sfx_*.wav + bgm_*.wav（16-bit PCM 单声道）
# 说明：
#   - SFX 为短促合成音，带淡出避免爆音
#   - BGM 为 8s 无缝循环：所有分音频率吸附到「整数个周期 / 时长」，
#     使 loop 点前后相位连续，运行时设 AudioStreamWAV.loop_mode 即可无缝循环
#   - 占位素材，后续可直接用真实音频覆盖同名文件（config/audio.json 无需改动）
# 用法：python tools/generate_audio_placeholders.py
# ============================================================================
import math
import os
import random
import struct
import sys
import wave

SR = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot_project", "assets", "audio")

random.seed(20260824)


# ----------------------------------------------------------------------------
# 写出 WAV（samples: list[float]，范围 [-1,1]）
# ----------------------------------------------------------------------------
def _write(name: str, samples: list, fade_in: float = 0.0, fade_out: float = 0.0) -> None:
    os.makedirs(OUT, exist_ok=True)
    n = len(samples)
    fi = int(fade_in * SR)
    fo = int(fade_out * SR)
    buf = bytearray()
    for i, s in enumerate(samples):
        g = 1.0
        if fi > 0 and i < fi:
            g *= i / fi
        if fo > 0 and i >= n - fo:
            g *= max(0.0, (n - i) / fo)
        v = int(max(-1.0, min(1.0, s * g)) * 32000)
        buf += struct.pack("<h", v)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(buf))
    print(f"  {name:22s} {n / SR:5.2f}s  {len(buf) / 1024:7.1f} KB")


# ----------------------------------------------------------------------------
# 基础合成
# ----------------------------------------------------------------------------
def _osc(phase: float, kind: str) -> float:
    if kind == "square":
        return 1.0 if math.sin(phase) >= 0.0 else -1.0
    if kind == "saw":
        return 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
    if kind == "tri":
        p = (phase / (2.0 * math.pi)) % 1.0
        return 4.0 * abs(p - 0.5) - 1.0
    return math.sin(phase)


def sfx_sweep(dur, f0, f1, kind="sine", noise_amt=0.0, tau=None, gain=1.0):
    """扫频 + 指数衰减 + 可选噪声。"""
    n = int(SR * dur)
    tau = tau if tau else dur * 0.35
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = f0 + (f1 - f0) * (i / n)
        phase += 2.0 * math.pi * f / SR
        e = math.exp(-t / tau)
        s = _osc(phase, kind) * e
        if noise_amt > 0.0:
            s += noise_amt * random.uniform(-1.0, 1.0) * e
        out.append(s * gain)
    return out


def sfx_arp(freqs, dur_each, kind="sine", gain=1.0):
    """琶音：依次播放若干音符。"""
    out = []
    for f in freqs:
        out.extend(sfx_sweep(dur_each, f, f, kind=kind, tau=dur_each * 0.6, gain=1.0))
    return [s * gain for s in out]


def sfx_noise(dur, tau, low_freq=None, gain=1.0):
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        e = math.exp(-t / tau)
        s = random.uniform(-1.0, 1.0)
        if low_freq:
            phase += 2.0 * math.pi * low_freq / SR
            s = 0.6 * s + 0.4 * math.sin(phase)
        out.append(s * e * gain)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    peak = max(1e-9, max(abs(x) for x in out))
    return [x / peak * 0.9 for x in out]


def bgm(dur, notes, tremolo=0.12, trem_hz=0.5, pulse_hz=0.0, pulse_depth=0.0, gain=0.8):
    """BGM 无缝循环：notes = [(target_freq, amp, phase), ...]。

    每个分音频率吸附为 round(f*dur)/dur —— 在 dur 内正好整数个周期，
    因此循环点相位连续、无爆音。
    """
    n = int(SR * dur)
    out = [0.0] * n
    for f_target, amp, ph in notes:
        cycles = max(1, round(f_target * dur))
        f = cycles / dur
        w = 2.0 * math.pi * f
        for i in range(n):
            out[i] += amp * math.sin(w * i / SR + ph)
    tc = max(1, round(trem_hz * dur))
    wt = 2.0 * math.pi * (tc / dur)
    pc = max(1, round(pulse_hz * dur)) if pulse_hz > 0.0 else 0
    wp = 2.0 * math.pi * (pc / dur) if pc else 0.0
    for i in range(n):
        g = 1.0 - tremolo * 0.5 * (1.0 + math.sin(wt * i / SR))
        if pc:
            g *= 1.0 - pulse_depth * 0.5 * (1.0 + math.sin(wp * i / SR))
        out[i] *= g
    peak = max(1e-9, max(abs(x) for x in out))
    return [x / peak * gain for x in out]


def main() -> None:
    # Windows GBK 控制台输出中文防 UnicodeEncodeError（对齐 stats_combat_logs.py）
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass
    print(f"输出目录: {OUT}")
    print("SFX:")
    _write("sfx_shoot.wav",
           sfx_sweep(0.12, 900, 260, "square", noise_amt=0.15, gain=0.5), fade_out=0.012)
    _write("sfx_hit.wav",
           mix(sfx_noise(0.09, 0.025, 120.0), sfx_sweep(0.09, 180, 80, "sine", gain=0.5)),
           fade_out=0.01)
    _write("sfx_enemy_die.wav",
           mix(sfx_sweep(0.28, 500, 120, "saw", noise_amt=0.10),
               sfx_noise(0.28, 0.08)), fade_out=0.03)
    _write("sfx_pickup.wav",
           sfx_sweep(0.10, 700, 1050, "sine", tau=0.03), fade_out=0.015)
    _write("sfx_coin.wav",
           sfx_arp([1250.0, 1750.0], 0.07), fade_out=0.015)
    _write("sfx_level_up.wav",
           sfx_arp([523.25, 659.25, 783.99, 1046.5], 0.12), fade_out=0.05)
    _write("sfx_hurt.wav",
           mix(sfx_sweep(0.20, 220, 120, "square", noise_amt=0.20, gain=0.6),
               sfx_noise(0.20, 0.06)), fade_out=0.02)
    _write("sfx_chest.wav",
           mix(sfx_arp([1200.0, 1500.0, 1800.0, 2200.0], 0.06, "tri"),
               sfx_noise(0.30, 0.12, gain=0.25)), fade_out=0.04)
    _write("sfx_ui_click.wav",
           sfx_sweep(0.045, 1100, 900, "sine", tau=0.012, gain=0.5), fade_out=0.008)
    _write("sfx_boss_roar.wav",
           mix(sfx_sweep(1.0, 70, 45, "saw", noise_amt=0.25, tau=0.5),
               sfx_noise(1.0, 0.4, 55.0)), fade_out=0.12)
    _write("sfx_game_over.wav",
           sfx_arp([440.0, 392.0, 330.0, 262.0], 0.18, "tri"), fade_out=0.08)
    _write("sfx_victory.wav",
           sfx_arp([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.13), fade_out=0.08)

    print("BGM（8s 无缝循环）:")
    _write("bgm_menu.wav", bgm(8.0, [
        (261.63, 0.60, 0.0), (329.63, 0.50, 0.5), (392.00, 0.45, 1.0), (130.81, 0.35, 0.0),
    ], tremolo=0.10, trem_hz=0.50))
    _write("bgm_day.wav", bgm(8.0, [
        (392.00, 0.55, 0.0), (493.88, 0.45, 0.6), (587.33, 0.40, 1.2), (196.00, 0.30, 0.0),
    ], tremolo=0.14, trem_hz=0.75))
    _write("bgm_night.wav", bgm(8.0, [
        (220.00, 0.60, 0.0), (261.63, 0.45, 0.7), (329.63, 0.40, 1.1), (110.00, 0.40, 0.0),
    ], tremolo=0.08, trem_hz=0.375))
    _write("bgm_boss.wav", bgm(8.0, [
        (146.83, 0.60, 0.0), (174.61, 0.50, 0.5), (220.00, 0.45, 1.0), (73.42, 0.50, 0.0),
    ], tremolo=0.10, trem_hz=1.00, pulse_hz=2.0, pulse_depth=0.25))
    print("完成。")


if __name__ == "__main__":
    main()
