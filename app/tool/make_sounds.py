"""Synthesises the game's sound effects into assets/audio/*.wav.

Run from app/:  python3 tool/make_sounds.py

Everything is generated from sine waves and noise, so the sounds carry no
third-party licence. Mono, 22.05 kHz, 16-bit.
"""
import math
import pathlib
import random
import struct
import wave

RATE = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio"


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.8 * 32767 / peak
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * scale)) for s in samples))


def env(i, n, attack=0.01, release=0.3):
    t = i / RATE
    total = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (total - t) / release) if release > 0 else 1.0
    return max(0.0, a * r)


def tone(freqs, dur, attack=0.01, release=0.2, vib=0.0):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for f, amp in freqs:
            s += amp * math.sin(2 * math.pi * f * t * (1 + vib * math.sin(2 * math.pi * 6 * t)))
        out.append(s * env(i, n, attack, release))
    return out


def concat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def mix(a, b, offset=0):
    n = max(len(a), len(b) + offset)
    out = [0.0] * n
    for i, s in enumerate(a):
        out[i] += s
    for i, s in enumerate(b):
        out[i + offset] += s
    return out


def main():
    rnd = random.Random(7)

    # Tap on an order: short glassy blip.
    write("tap", tone([(1320, 1.0), (2640, 0.3)], 0.06, 0.002, 0.05))

    # Probe ping: rising sonar chirp with a soft tail.
    n = int(RATE * 0.45)
    ping = [math.sin(2 * math.pi * (700 + 900 * (i / n)) * i / RATE) * env(i, n, 0.005, 0.35) for i in range(n)]
    write("probe", ping)

    # Superposition shimmer: detuned cluster that wavers, used while the
    # outcome cells flicker.
    shimmer = tone([(523, 0.5), (659, 0.4), (784, 0.4), (531, 0.4), (1046, 0.2)], 0.55, 0.05, 0.25, vib=0.01)

    # Collapse: shimmer cut by a low thump and a bright click. The game's one
    # unmistakable sound.
    n = int(RATE * 0.5)
    thump = [math.sin(2 * math.pi * (110 - 60 * i / n) * i / RATE) * math.exp(-6 * i / n) for i in range(n)]
    click = [(rnd.random() * 2 - 1) * math.exp(-i / 120) for i in range(800)]
    collapse = mix(shimmer, mix(thump, click), int(RATE * 0.45))
    write("collapse", collapse)

    # Hit on the enemy: noise burst through a falling filter.
    n = int(RATE * 0.35)
    hit, y = [], 0.0
    for i in range(n):
        a = 0.05 + 0.5 * (1 - i / n)
        y += a * ((rnd.random() * 2 - 1) - y)
        hit.append(y * math.exp(-5 * i / n))
    write("hit", hit)

    # Damage taken: lower, rougher burst.
    n = int(RATE * 0.4)
    hurt, y = [], 0.0
    for i in range(n):
        y += 0.08 * ((rnd.random() * 2 - 1) - y)
        hurt.append((y + 0.3 * math.sin(2 * math.pi * 70 * i / RATE)) * math.exp(-4 * i / n))
    write("hurt", hurt)

    # Victory: shanty-like rising arpeggio, A minor to C major.
    notes = [440, 523, 659, 784, 880]
    write("victory", concat(*[tone([(f, 1.0), (f * 2, 0.25)], 0.16, 0.005, 0.08) for f in notes], tone([(1046, 1.0), (523, 0.5)], 0.6, 0.01, 0.5)))

    # Defeat: falling minor line.
    notes = [440, 392, 349, 330]
    write("defeat", concat(*[tone([(f, 1.0), (f / 2, 0.4)], 0.22, 0.01, 0.12) for f in notes], tone([(220, 1.0), (110, 0.6)], 0.8, 0.01, 0.7)))

    # Unlock: two bright bells.
    write("unlock", concat(tone([(988, 1.0), (1976, 0.3)], 0.18, 0.003, 0.15), tone([(1318, 1.0), (2636, 0.3)], 0.5, 0.003, 0.45)))


if __name__ == "__main__":
    main()
