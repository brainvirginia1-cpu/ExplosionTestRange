"""Synthesize close and distant explosion mixes for the game's audio tiers."""

from pathlib import Path

import numpy as np
from scipy.io.wavfile import write
from scipy.signal import butter, fftconvolve, sosfilt

OUTPUT = Path(__file__).resolve().parents[2] / "assets" / "sounds"
RATE = 32000
# Ground, thermal, elevated and underground timbres.
TIMBRES = [
    (4_900, 1.00, 1.00),
    (3_800, 1.22, 0.93),
    (6_100, 0.87, 0.87),
    (980, 0.85, 0.46),
]

# Designed patterns informed by the public recordings' transient and tail envelopes.
TIGHT_RETURNS = ((0.094, 0.25), (0.21, 0.17), (0.35, 0.10), (0.58, 0.06))
OPEN_RETURNS = ((0.22, 0.27), (0.44, 0.21), (0.72, 0.19), (1.04, 0.16),
                (1.33, 0.11), (1.66, 0.085), (2.07, 0.054))


def band_noise(rng, frames, low, high):
    noise = rng.standard_normal(frames)
    filtered = sosfilt(
        butter(2, (low, high), fs=RATE, btype="bandpass", output="sos"), noise
    )
    return filtered / filtered.std()


def peak_round(audio):
    amplitude = np.abs(audio)
    knee = 0.83
    ceiling = 0.97
    rounded = knee + (ceiling - knee) * np.tanh((amplitude - knee) / (ceiling - knee))
    return np.where(amplitude > knee, np.sign(audio) * rounded, audio)


def add_echo(dry, tier, distant, seed, style=0):
    rng = np.random.default_rng(seed)
    open_space = np.clip((tier - 1) / 4, 0, 1)
    if distant:
        open_space = max(0.58, open_space)
    stretch = 0.73 + 0.10 * tier
    decay = (0.31 + 0.15 * tier) * (1.26 if distant else 1.0)
    impulse = np.zeros(round(RATE * (0.75 + 7.2 * decay)))
    wet = 1.17 if distant else 0.95
    for pattern, weight in ((TIGHT_RETURNS, 1.0-open_space), (OPEN_RETURNS, open_space)):
        for delay, gain in pattern:
            start = round(RATE * delay * stretch)
            if start < len(impulse):
                impulse[start] += gain * wet * weight
    for delay in np.arange(0.48 * stretch, len(impulse) / RATE - 0.035, 0.027):
        sample = round(RATE * (delay + rng.uniform(0, 0.023)))
        gain = (0.041 + 0.047 * open_space) * wet * np.exp(-(delay - 0.48 * stretch) / decay)
        impulse[sample] += rng.choice([-1, 1]) * gain

    bounce = fftconvolve(dry, impulse)
    cutoff = 1100 if style == 3 else (2250 if distant else 4100)
    bounce = sosfilt(
        butter(2, (42, cutoff), fs=RATE, btype="bandpass", output="sos"), bounce
    )
    bounce[: len(dry)] += dry
    return peak_round(bounce)


def render(style, tier):
    edge_hz, duration, surface_noise = TIMBRES[style]
    size = tier / 6.0
    rng = np.random.default_rng(84131 + style * 235 + tier)
    time = np.arange(round(RATE * (2.35 + 0.26 * tier + 0.23 * tier**2))) / RATE

    def band(low, high):
        return band_noise(rng, time.size, low, high)

    def envelope(start, attack, decay):
        local = np.maximum(0, time - start)
        return -np.expm1(-local / attack) * np.exp(-local / decay)

    edge_hz *= 0.68
    snap = band(edge_hz * 0.58, edge_hz * 1.35) * envelope(0, 0.0012, 0.007+size*0.006)
    body_crack = band(240, edge_hz * 0.69) * envelope(0.003, 0.0025, 0.026+size*0.023)
    bass = band(29, 104)
    weight = band(64, 218)
    grit = band(270, 1330)
    pitch = 74.0 - tier * 6.4
    hit = np.zeros_like(time)
    for multiplier, gain, delay in ((1.0, 0.79, 0.001), (1.49, 0.24, 0.005)):
        local = np.maximum(0, time-delay)
        phase = 2*np.pi*(pitch*multiplier*local+0.38*-np.expm1(-local/0.036))
        swell = envelope(delay, 0.0045, (0.066+size*0.105)*duration / multiplier**0.4)
        hit += np.sin(phase)*swell*gain
    pressure = (weight*0.52+bass*(0.57+size*0.29))*envelope(
        0.004, 0.007+size*0.019, (0.086+size*0.32)*duration
    )
    ridge = 0.49*envelope(0.047,0.016,0.075+0.12*size)
    ridge += 0.23*envelope(0.11+size*0.09,0.021,0.075+0.14*size)
    if tier >= 2:
        # Uneven peaks fuse into a long exterior rumble on the heavier presets.
        for i in range(tier+1):
            onset = 0.12+i*(0.11+size*0.34)+rng.uniform(-0.022,0.065)
            ridge += 0.78**i*envelope(onset,0.032+0.060*size,0.19+0.49*size)
    rumble = ridge*(0.62*bass+0.39*weight+0.062*grit)
    snap_gain = (0.37-0.14*size)*surface_noise
    near = snap*snap_gain+body_crack*(0.49-0.12*size)+hit*0.93+pressure+rumble*0.56
    far = snap*snap_gain*0.32+body_crack*0.25+hit*0.62+pressure*0.95+rumble*0.80
    if style == 1:
        rush = (band(225, 2270)*0.46+weight*0.25)*envelope(
            0.052,0.058+size*0.035,0.26+0.60*size
        )
        near += rush+grit*envelope(0.14,0.013,0.19)*0.35
        far += rush*0.66
    elif style == 3:
        body = (bass*0.65+weight*0.21)*envelope(0.046,0.042,0.31+0.45*size)
        near = near*0.79+body
        far = far*0.74+body

    far = sosfilt(butter(2, 3100 if style != 3 else 1350, fs=RATE, output="sos"), far)
    fade = np.clip((time[-1] - time) / 0.42, 0.0, 1.0)
    if style == 0:
        name = "range_burst" if tier == 1 else f"range_burst_{tier}"
    else:
        name = f"style_{style}_{tier}"
    for distant, stem, signal in ((False, name, near), (True, f"roll_{style}_{tier}", far)):
        dry = np.tanh(signal * (1.14 if not distant else 1.02)) * fade * 0.90
        audio = add_echo(dry, tier, distant, 21503 + style * 11 + tier, style)
        write(OUTPUT / (stem + ".wav"), RATE, np.rint(audio * 32767).astype("<i2"))


if __name__ == "__main__":
    for style in range(len(TIMBRES)):
        for tier in range(7):
            render(style, tier)
