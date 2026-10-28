#!/usr/bin/env python3
"""On-demand Ryotunes stereo PCM -> small newline-delimited JSON frames.

Requires existing ffmpeg and pactl. Captures ONLY a Pulse/PipeWire output monitor.
Never writes audio to a file; terminates ffmpeg on exit. No fake input frames.
"""
from __future__ import annotations

import array
import json
import math
import os
import signal
import subprocess
import sys

RATE = 48000
FRAMES = 1920  # 25 fps, one process shared by BOTH scope views
TRACE_POINTS = 180
PHASE_POINTS = 240


def analyse(audio: array.array, last_scale: float) -> tuple[dict, float]:
    left = audio[::2]
    right = audio[1::2]
    n = min(len(left), len(right))
    if n < 2:
        raise ValueError("Not enough stereo samples")

    power_l = sum(float(a) * a for a in left)
    power_r = sum(float(b) * b for b in right)
    cross = sum(float(a) * float(b) for a, b in zip(left, right))
    denom = math.sqrt(power_l * power_r)
    phase = max(-1.0, min(1.0, cross / denom)) if denom > 1e-12 else 0.0
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right))
    rms = math.sqrt((power_l + power_r) / (2 * n))
    # The amplitude scaling is intentionally indicated in the UI: the shapes
    # are measured stereo samples, but a quiet master should still be visible.
    desired = min(18.0, 0.85 / max(0.04, peak))
    scale = 0.75 * last_scale + 0.25 * desired
    if rms < 0.0001:
        return {"wave": [], "xy": [], "phase": 0.0, "rms": 0.0}, scale

    mono = [(float(a) + float(b)) * 0.5 for a, b in zip(left, right)]
    # Rising zero-crossing triggers keep a roughly periodic tone stable.
    start = next((j for j in range(12, min(n - 1000, 650))
                  if mono[j] <= 0 and mono[j + 1] > 0), 0)
    window = min(1000, n - start)
    wave = [round(max(-1, min(1, mono[start + (i * (window - 1) // (TRACE_POINTS - 1))] * scale)), 4)
            for i in range(TRACE_POINTS)]
    xy = [[round(max(-1, min(1, float(left[i * (n - 1) // (PHASE_POINTS - 1)]) * scale)), 4),
           round(max(-1, min(1, float(right[i * (n - 1) // (PHASE_POINTS - 1)]) * scale)), 4)]
          for i in range(PHASE_POINTS)]
    return {"wave": wave, "xy": xy, "phase": round(phase, 3), "rms": round(rms, 5)}, scale


def self_test() -> None:
    def stereo(fn):
        data = array.array("f")
        for i in range(FRAMES):
            l = 0.12 * math.sin(i * 2 * math.pi * 440 / RATE)
            r = fn(l, i)
            data.extend((l, r))
        return data

    same, _ = analyse(stereo(lambda l, i: l), 1.0)
    inverse, _ = analyse(stereo(lambda l, i: -l), 1.0)
    independent, _ = analyse(stereo(lambda l, i: 0.12 * math.cos(i * 2 * math.pi * 440 / RATE)), 1.0)
    assert len(same["wave"]) == TRACE_POINTS
    assert len(same["xy"]) == PHASE_POINTS
    assert same["phase"] > 0.999, same["phase"]
    assert inverse["phase"] < -0.999, inverse["phase"]
    assert abs(independent["phase"]) < 0.05, independent["phase"]
    assert all(-1 <= x <= 1 for x in same["wave"])
    print("PASS: stereo correlation, real sample trace and frame bounds")


def sink_monitor() -> str:
    sink = subprocess.check_output(["pactl", "get-default-sink"], text=True, timeout=5).strip()
    if not sink or "/" in sink or "\n" in sink:
        raise RuntimeError("Invalid default PipeWire sink")
    source = sink + ".monitor"
    lines = subprocess.check_output(["pactl", "list", "short", "sources"], text=True, timeout=5)
    names = {parts[1] for line in lines.splitlines() if (parts := line.split()) and len(parts) > 1}
    if source not in names:
        raise RuntimeError("Default output monitor is unavailable")
    return source


def capture() -> None:
    source = sink_monitor()
    command = [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-f", "pulse", "-sample_rate", str(RATE), "-channels", "2", "-i", source,
        "-vn", "-ac", "2", "-f", "f32le", "-acodec", "pcm_f32le", "-",
    ]
    proc = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, bufsize=FRAMES * 8)
    try:
        assert proc.stdout is not None
        scale = 1.0
        while True:
            raw = proc.stdout.read(FRAMES * 8)
            if len(raw) != FRAMES * 8:
                break
            audio = array.array("f")
            audio.frombytes(raw)
            if sys.byteorder != "little":
                audio.byteswap()
            payload, scale = analyse(audio, scale)
            print(json.dumps(payload, separators=(",", ":")), flush=True)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)


def main() -> None:
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    try:
        capture()
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        print(json.dumps({"error": str(error)}), flush=True)
        sys.exit(1)
    except BrokenPipeError:
        return


if __name__ == "__main__":
    main()
