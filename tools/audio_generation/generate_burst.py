"""Synthesize original game sound assets as mono 16-bit WAV."""
from array import array
from math import exp, pi, sin, tanh
from pathlib import Path
from random import Random
import sys
import wave

SAMPLE_RATE = 44100
OUTPUT = Path(__file__).resolve().parents[2] / "assets" / "sounds"


def write_wave(name, values, peak=0.86):
    lift = peak / max(abs(value) for value in values)
    pcm = array("h", (round(value * lift * 32767) for value in values))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(OUTPUT / (name + ".wav")), "wb") as sound:
        sound.setparams((1, 2, SAMPLE_RATE, 0, "NONE", "not compressed"))
        sound.writeframes(pcm.tobytes())


def burst(index):
    random = Random(7931 + index * 2789)
    duration = (2.2, 2.85, 3.45, 4.65, 6.2, 8.6, 11.2)[index]
    fundamental = (67.0, 59.0, 51.0, 44.0, 38.0, 34.0, 30.0)[index]
    body_time = (0.19, 0.28, 0.40, 0.63, 0.94, 1.31, 1.78)[index]
    tail_time = (0.40, 0.53, 0.68, 0.98, 1.34, 1.83, 2.42)[index]
    sub_noise = low_noise = upper_noise = 0.0
    phase = 0.0
    signal = array("f")
    reflections = [(0.15 + 0.026 * index, 0.36), (0.31 + 0.047 * index, 0.25), (0.59 + 0.083 * index, 0.14)]
    for n in range(round(SAMPLE_RATE * duration)):
        t = n / SAMPLE_RATE
        white = random.uniform(-1.0, 1.0)
        sub_noise += 0.012 * (white - sub_noise)
        low_noise += 0.051 * (white - low_noise)
        upper_noise += 0.20 * (white - upper_noise)
        pitch = fundamental + (48.0 - index * 3.2) * exp(-t * 16.0)
        phase += 2.0 * pi * pitch / SAMPLE_RATE
        attack = min(1.0, t * 390)
        bass = (sin(phase) * 0.86 + sin(phase * 1.92 + 1.1) * 0.27 + sub_noise * 2.9)
        bass *= exp(-t / body_time) * attack
        crack = (white * 0.39 + upper_noise * 0.63) * exp(-t * 34.0) * min(1.0, t * 2200)
        mids = (low_noise * 1.2 + upper_noise * 0.25) * exp(-t / (body_time * 0.93))
        rumble = (sub_noise * 1.74 + low_noise * 0.42) * exp(-t / tail_time)
        rumble *= min(1.0, t * 9.0) * (0.9 + 0.10 * sin(21.0 * t))
        wall = 0.0
        for delay, weight in reflections:
            local = t - delay
            if local > 0:
                wall += weight * min(1.0, local * 43.0) * exp(-local * 8.8) * (low_noise * 2.1 + sin(phase * 0.74))
        fade = min(1.0, (duration - t) * 3.4)
        signal.append(tanh((bass + crack + mids + rumble + wall) * 1.06) * fade)
    stem = "range_burst" if index == 1 else f"range_burst_{index}"
    write_wave(stem, signal, peak=(0.86 + index * 0.009))


def impact():
    random = Random(9401)
    signal = array("f")
    floor = 0.0
    texture = 0.0
    for index in range(int(SAMPLE_RATE * 0.78)):
        t = index / SAMPLE_RATE
        noise = random.uniform(-1.0, 1.0)
        floor += 0.028 * (noise - floor)
        texture += 0.13 * (noise - texture)
        pulse = 0.0
        for delay, decay, weight in ((0.0, 29.0, 1.0), (0.074, 49.0, 0.33), (0.184, 36.0, 0.22)):
            age = t - delay
            if age >= 0.0:
                pulse += weight * min(1.0, age * 1100.0) * exp(-age * decay)
        signal.append(pulse * (floor * 0.87 + texture * 0.25))
    write_wave("range_impact", signal, peak=0.61)


def flyby():
    random = Random(7253)
    signal = array("f")
    low = 0.0
    duration = 4.6
    for index in range(int(SAMPLE_RATE * duration)):
        t = index / SAMPLE_RATE
        noise = random.uniform(-1.0, 1.0)
        low += 0.020 * (noise - low)
        body = sin(2 * pi * (75 * t + 2.7 * sin(t * 1.4))) * 0.11
        fade = min(1.0, t * 11) * min(1.0, (duration - t) * 6)
        signal.append((0.19 * noise + 0.69 * low + body) * fade)
    write_wave("range_flyby", signal, peak=0.64)


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for variant in range(7):
        burst(variant)
    impact()
    flyby()
