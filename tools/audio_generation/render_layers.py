"""Render additional foley and recorded thunder layers for the range."""
from pathlib import Path
import subprocess

from render_mix import OUTPUT, RATE, add_echo
import numpy as np
from scipy.io.wavfile import write
from scipy.signal import butter, sosfilt


def make_layer(name, seconds, seed, build, echo_tier):
    rng = np.random.default_rng(seed)
    t = np.arange(round(RATE * seconds)) / RATE

    def band(low, high):
        noise = rng.standard_normal(t.size)
        filtered = sosfilt(butter(2, [low, high], fs=RATE, btype="bandpass", output="sos"), noise)
        return filtered / max(filtered.std(), 1e-9)

    def envelope(start, attack, decay):
        age = np.maximum(0, t-start)
        return -np.expm1(-age/attack)*np.exp(-age/decay)

    audio = build(t, band, envelope, rng)
    audio *= np.clip((t[-1]-t)/0.40, 0, 1)
    audio = np.tanh(audio)*0.79
    if echo_tier is not None:
        audio = add_echo(audio,echo_tier,False,seed+11)
    write(OUTPUT / (name+".wav"), RATE, np.rint(audio*32767).astype("<i2"))


def gravel(t, band, envelope, rng):
    sand = band(290, 1030)
    soil = band(112, 540)
    stone = band(315, 855)
    audio = (0.27 * sand + 0.17 * soil) * envelope(0.10, 0.115, 0.34)
    strikes = [0.16, 0.225, 0.315, 0.49, 0.62, 0.86, 1.08]
    for i, start in enumerate(strikes):
        body = soil * rng.uniform(0.46, 0.71) + stone * rng.uniform(0.17, 0.37)
        fade = 0.42 * np.exp(-start * 1.35)
        audio += fade * body * envelope(start, 0.0025 + i * 0.0004, 0.019 + start * 0.016)
    return audio


def render_thunder(name, source, start, duration, delay):
    path = Path(__file__).with_name("sources") / source
    decoded = subprocess.check_output([
        "ffmpeg", "-v", "error", "-ss", str(start), "-i", str(path),
        "-t", str(duration), "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-",
    ])
    audio = np.frombuffer(decoded, dtype="<f4")
    bandpass = butter(3, [25, 1500], fs=RATE, btype="bandpass", output="sos")
    rumble = sosfilt(bandpass, audio)
    time = np.arange(rumble.size) / RATE
    fade_in = np.sin(0.5 * np.pi * np.clip(time / 0.36, 0, 1)) ** 2
    fade_out = np.sin(0.5 * np.pi * np.clip((time[-1] - time) / 2.6, 0, 1)) ** 2
    rumble *= fade_in * fade_out
    level = np.percentile(np.abs(rumble), 97)
    rumble = 0.82 * np.tanh(rumble * 0.56 / max(level, 1e-9))
    # Silence keeps the onset behind the main impact and inherits its travel delay.
    mix = np.pad(rumble, (round(delay * RATE), 0))
    write(OUTPUT / (name + ".wav"), RATE, np.rint(mix * 32767).astype("<i2"))


def thermal(t, band, envelope, rng):
    air = band(220, 1210)
    crack = band(420, 1180)
    low = band(34, 158)
    audio = 0.61*air*envelope(0.07, 0.18, 0.71) + 0.53*low*envelope(0.32, 0.14, 1.32)
    for start in [0.16, 0.39, 0.56, 0.96, 1.23]:
        audio += 0.16*crack*envelope(start,0.007,0.031)
    return audio


if __name__ == "__main__":
    make_layer("burst_grit_tail", 1.70, 83721, gravel, None)
    # CC0 field recordings by billgrip and Fission9.
    # https://freesound.org/people/billgrip/sounds/151447/
    # https://freesound.org/people/Fission9/sounds/581122/
    render_thunder("burst_thunder_tail", "billgrip-151447.mp3", 33.25, 11.5, 0.62)
    render_thunder("burst_thunder_tail_2", "fission9-581122.mp3", 16.0, 14.0, 0.84)
    make_layer("burst_thermal_tail", 5.2, 92481, thermal, 3)
