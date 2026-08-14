"""Synthesize the pause transition voice: a low cinematic swell.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python tools/build_pause_sfx.py

Writes assets/audio/ui/pause_open.wav and pause_close.wav.

---------------------------------------------------------------------------
WHY SYNTHESIZED
---------------------------------------------------------------------------
The owner asked for the feel of Battlefield 1's redeploy sting on the pause
camera push -- a deep, muffled swell that says the world just became a shot.
No such take exists in the project's audio, and shipping a copy of DICE's
recording was never an option. So the sound is BUILT: an original three-part
construction (sub bed, dropping whoomp, cold air) that aims at the GESTURE --
low, slow, larger than the menu -- not at the recording.

Why under Blender: same reason as build_ambience_loops.py -- the system Python
has no numpy and there is no ffmpeg here; Blender ships both.

pause_close is the same gesture reversed in spirit: shorter, rising, and much
quieter -- the gate lifting, the world resuming. Both target the project's
-20 dBFS RMS neighbourhood so they sit with the ambience loops.
"""

import math
import os
import wave

import numpy as np

SAMPLE_RATE = 44100
TARGET_RMS_DBFS = -20.0

OUT_DIR = "assets/audio/ui"


def _smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def _sweep(duration, freq_start, freq_end, envelope):
    """A sine whose pitch glides exponentially, phase-integrated."""
    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    ratio = freq_end / freq_start
    # Instantaneous frequency: exponential glide. Integrate for phase.
    freq = freq_start * np.power(ratio, t / duration)
    phase = np.cumsum(freq) / SAMPLE_RATE * 2.0 * math.pi
    return np.sin(phase) * envelope


def _one_pole_lowpass(signal, cutoff_hz):
    """Time-varying one-pole lowpass. cutoff_hz is an array per sample."""
    alpha = 1.0 - np.exp(-2.0 * math.pi * np.maximum(cutoff_hz, 1.0) / SAMPLE_RATE)
    out = np.empty_like(signal)
    y = 0.0
    # The loop is the point: cutoff moves per sample, so np.convolve cannot help.
    for i in range(signal.size):
        y += alpha[i] * (signal[i] - y)
        out[i] = y
    return out


def _write(name, signal):
    os.makedirs(OUT_DIR, exist_ok=True)
    rms = float(np.sqrt(np.mean(np.square(signal))))
    signal = signal * (10.0 ** (TARGET_RMS_DBFS / 20.0) / max(rms, 1e-10))
    peak = float(np.max(np.abs(signal)))
    if peak > 1.0:
        signal = signal / peak
        peak = 1.0
    rms = float(np.sqrt(np.mean(np.square(signal))))
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes((signal * 32767.0).astype(np.int16).tobytes())
    print("build_pause_sfx: %s  %.2fs  peak %.2f  RMS %.1f dBFS"
          % (path, signal.size / SAMPLE_RATE, peak, 20.0 * math.log10(max(rms, 1e-10))))


def build_open():
    """The deploy swell: ~1.5 s. A sub bed rising, a whoomp dropping through
    it, and cold air swelling over both. Fast enough to answer ESC, slow
    enough to be a camera move."""
    duration = 1.5
    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    # Sub bed: 52 Hz, swelling in over 0.3 s, released over the last 0.55 s.
    env_bed = _smoothstep(t / 0.30) * (1.0 - _smoothstep((t - 0.95) / 0.55))
    bed = np.sin(2.0 * math.pi * 52.0 * t) * env_bed * 0.9

    # The whoomp: 170 -> 44 Hz over 0.5 s, fast attack, exponential tail.
    env_drop = _smoothstep(t / 0.03) * np.exp(-t / 0.26)
    drop = _sweep(duration, 170.0, 44.0, env_drop) * 0.75

    # Cold air: noise through a lowpass that opens and closes (400 -> 1100 ->
    # 350 Hz), swelling for 0.4 s and breathing out over the rest.
    rng = np.random.default_rng(20260813)
    noise = rng.standard_normal(n)
    cutoff = 400.0 + 700.0 * _smoothstep(t / 0.40) * (1.0 - _smoothstep((t - 0.55) / 0.9))
    air = _one_pole_lowpass(noise, cutoff)
    air /= max(float(np.max(np.abs(air))), 1e-10)
    env_air = _smoothstep(t / 0.40) * (1.0 - _smoothstep((t - 0.55) / 0.90))
    air *= env_air * 0.22

    # A soft transient at the head -- the gate landing, not an impact.
    transient_env = np.exp(-t / 0.018) * (t < 0.08)
    transient = np.sin(2.0 * math.pi * 68.0 * t) * transient_env * 0.35

    return bed + drop + air + transient


def build_close():
    """The lift: ~0.65 s, the mirror gesture. Rising sweep, quick swell of
    air, short tail. Quieter than the open -- returning should cost less."""
    duration = 0.65
    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    env_rise = _smoothstep(t / 0.02) * np.exp(-t / 0.30)
    rise = _sweep(duration, 46.0, 96.0, env_rise) * 0.65

    bed_env = _smoothstep(t / 0.05) * (1.0 - _smoothstep((t - 0.30) / 0.35))
    bed = np.sin(2.0 * math.pi * 55.0 * t) * bed_env * 0.5

    rng = np.random.default_rng(20260814)
    noise = rng.standard_normal(n)
    cutoff = 900.0 * (1.0 - _smoothstep(t / 0.5)) + 250.0
    air = _one_pole_lowpass(noise, cutoff)
    air /= max(float(np.max(np.abs(air))), 1e-10)
    air *= _smoothstep(t / 0.06) * np.exp(-t / 0.22) * 0.15

    return rise + bed + air


def main():
    _write("pause_open.wav", build_open())
    _write("pause_close.wav", build_close())


main()
