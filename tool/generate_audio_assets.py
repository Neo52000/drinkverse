#!/usr/bin/env python3
"""Génère les sons placeholder de DrinkVessel (assets/audio/*.wav).

Sons entièrement synthétiques (bruit filtré + oscillateurs), stdlib Python
uniquement (wave/struct/math/random) — aucune dépendance réseau, aucune
question de licence. Ce ne sont pas des enregistrements réels : ils peuvent
être remplacés à tout moment en déposant un fichier du même nom dans
assets/audio/ (drink_audio_service.dart ne dépend que du nom de fichier).

Usage: python3 tool/generate_audio_assets.py
"""

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio"


def write_wav(name: str, samples: list[float]) -> None:
    path = OUT_DIR / name
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        clipped = (max(-1.0, min(1.0, s)) for s in samples)
        f.writeframes(struct.pack(f"<{len(samples)}h", *(int(s * 32767) for s in clipped)))
    print(f"wrote {path} ({len(samples) / SAMPLE_RATE:.2f}s)")


def fade_loop_edges(samples: list[float], fade_samples: int) -> None:
    """Fade-in/out at both ends so ReleaseMode.loop doesn't click at the seam."""
    n = len(samples)
    fade_samples = min(fade_samples, n // 2)
    for i in range(fade_samples):
        g = i / fade_samples
        samples[i] *= g
        samples[n - 1 - i] *= g


def one_pole_lowpass(samples: list[float], cutoff: float) -> list[float]:
    out = [0.0] * len(samples)
    prev = 0.0
    for i, s in enumerate(samples):
        prev = prev + cutoff * (s - prev)
        out[i] = prev
    return out


def generate_pour_loop(rng: random.Random) -> list[float]:
    n = SAMPLE_RATE  # 1s
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    body = one_pole_lowpass(noise, 0.06)
    rumble = one_pole_lowpass(noise, 0.015)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        wobble = 0.75 + 0.25 * math.sin(2 * math.pi * 4.2 * t) * math.sin(2 * math.pi * 0.7 * t)
        samples.append((body[i] * 0.55 + rumble[i] * 0.75) * wobble)
    peak = max(abs(s) for s in samples) or 1.0
    samples = [s / peak * 0.75 for s in samples]
    fade_loop_edges(samples, int(0.02 * SAMPLE_RATE))
    return samples


def generate_fizz_loop(rng: random.Random) -> list[float]:
    n = SAMPLE_RATE  # 1s
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    low = one_pole_lowpass(noise, 0.35)
    hiss = [noise[i] - low[i] for i in range(n)]  # crude high-pass via spectral subtraction
    samples = [h * 0.32 for h in hiss]
    # Sparse crackle pops.
    pop_count = int(n / SAMPLE_RATE * 90)
    for _ in range(pop_count):
        start = rng.randrange(0, n - 200)
        strength = rng.uniform(0.25, 0.7)
        decay_len = rng.randrange(40, 180)
        for k in range(decay_len):
            if start + k >= n:
                break
            env = strength * math.exp(-k / (decay_len * 0.28))
            samples[start + k] += rng.uniform(-1, 1) * env
    fade_loop_edges(samples, int(0.02 * SAMPLE_RATE))
    return samples


def generate_refill_clink() -> list[float]:
    duration = 0.22
    n = int(SAMPLE_RATE * duration)
    freqs = [2200, 3300, 4400]
    samples = [0.0] * n
    for f in freqs:
        amp = 1.0 / len(freqs)
        for i in range(n):
            t = i / SAMPLE_RATE
            env = math.exp(-t * 18)
            samples[i] += amp * env * math.sin(2 * math.pi * f * t)
    peak = max(abs(s) for s in samples) or 1.0
    return [s / peak * 0.85 for s in samples]


def generate_empty_glass(rng: random.Random) -> list[float]:
    duration = 0.45
    n = int(SAMPLE_RATE * duration)
    samples = [0.0] * n
    # Two quick descending "glug" swoops.
    for bump_start, bump_len in ((0.0, 0.22), (0.20, 0.25)):
        start_i = int(bump_start * SAMPLE_RATE)
        len_i = int(bump_len * SAMPLE_RATE)
        for i in range(len_i):
            if start_i + i >= n:
                break
            t = i / len_i
            freq = 480 - 320 * t
            env = math.sin(math.pi * t) * 0.8
            phase = 2 * math.pi * freq * (i / SAMPLE_RATE)
            samples[start_i + i] += env * math.sin(phase)
    noise = [rng.uniform(-1, 1) * 0.05 for _ in range(n)]
    texture = one_pole_lowpass(noise, 0.2)
    for i in range(n):
        samples[i] += texture[i]
    peak = max(abs(s) for s in samples) or 1.0
    return [s / peak * 0.8 for s in samples]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rng = random.Random(20260728)
    write_wav("pour_loop.wav", generate_pour_loop(rng))
    write_wav("fizz_loop.wav", generate_fizz_loop(rng))
    write_wav("refill_clink.wav", generate_refill_clink())
    write_wav("empty_glass.wav", generate_empty_glass(rng))


if __name__ == "__main__":
    main()
