"""Turn the owner's five ambience takes into seamless loops.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python tools/build_ambience_loops.py -- \
        [--measure] [--only wind_mid]

`--measure` reports and writes nothing. Without it the loops are written to
`assets/audio/ambience/`, where `AmbienceMap.sound_folder` resolves them by
name.

---------------------------------------------------------------------------
WHY THIS RUNS UNDER BLENDER
---------------------------------------------------------------------------
Same reason as `tools/cut_animal_calls.py`: Godot can load an mp3 and tell you
its length but exposes no way to read the decoded samples back out, `ffmpeg` is
not installed on this machine, and the system Python has no numpy. Blender ships
both audaspace and numpy and is the only decoder here.

---------------------------------------------------------------------------
THE FILENAMES ARE WRONG, AND THAT IS THE FIRST FINDING
---------------------------------------------------------------------------
Measured band shares of the three wind takes as supplied:

    file             20-80  80-250  .25-.8k  .8-2.5k  2.5-8k
    wind_low.wav       4.8     0.5     79.9      9.9     0.0
    wind_mid.mp3      36.5    35.6     15.8      0.7     0.1
    wind_high.wav      1.8     4.7      7.6     85.6     0.3

`wind_low` and `wind_mid` are the wrong way round. `wind_mid.mp3` is the one
with 71% of its energy under 250 Hz; `wind_low.wav` is a 250-800 Hz band with
no bottom in it at all.

Shipping them under the supplied names would have given `wind_low` -- the layer
present ~78% of a valley day, and the ONLY layer that survives a threat -- a
thin mid band with no body, while the actual body of the air sounded for 24% of
the time and vanished whenever a bear was near. That is the exact inverse of
GDD section 9's 抽走高频层，只剩低频. So the assignment below is by
MEASUREMENT, and `CUTS` records which take feeds which layer.

---------------------------------------------------------------------------
THE JOB IS THE JOIN, NOT THE LENGTH
---------------------------------------------------------------------------
`wind_low` plays essentially continuously, and in a game this quiet a click
every cycle is the loudest thing on screen. Cutting a take to length is trivial;
making the last sample join the first is the whole task.

Three things are done about it, in this order:

  1. THE LOOP POINT IS SEARCHED FOR, NOT CHOSEN. For a target length the script
     slides the start and scores every candidate on how alike the two regions
     the crossfade will blend actually are -- level in dB plus a log-band
     spectral distance. A join between two passages that already match needs the
     least help from the crossfade, and the crossfade is the part that can be
     heard.

  2. THE CROSSFADE IS EQUAL-POWER, NOT LINEAR. Two different stretches of wind
     are uncorrelated noise. Mixed with linear ramps their POWERS add rather
     than their amplitudes, so the middle of the fade sits about 3 dB down -- a
     hole arriving once per cycle, as audible as the click it replaced. sin/cos
     ramps hold the power flat.

  3. THE BAND-LIMITING IS DONE IN THE FREQUENCY DOMAIN, AFTER THE LOOP IS BUILT.
     An FFT filter is a CIRCULAR convolution: it treats the signal as already
     periodic, so whatever it does at the end it does identically at the start
     and it cannot disturb the join it wraps around. A time-domain FIR would
     smear across the loop point and undo step 1.

`join_report()` then checks the result rather than assuming it: the step across
the wrap is compared against the take's own distribution of adjacent-sample
steps, and a wrap under the 99.9th percentile of the signal's own motion is
indistinguishable from the signal.

---------------------------------------------------------------------------
AND THE BANDS HAVE TO STAY APART
---------------------------------------------------------------------------
`AmbienceLayer`'s whole design is that the three wind voices are different parts
of the same wind -- low is the body of the air, mid is the gust, high is the
hiss. Three broadband recordings played together do not sum to that design; they
sum to mud, three times as loud in the bottom as any one of them.

The old `wind_low` and 3.6 s `wind_mid` were replaced on 2026-08-13 with two
non-overlapping passages from lwdickens' "winter wind in trees" (Freesound
261226, CC0 1.0). The reproducible source is the original 48 kHz/24-bit WAV,
`winter_wind_in_trees_261226.wav`, SHA-256
4046FBF42173A54B4216FAF4EDF2515C59F6BF70E6920B00375A62BB84AD420A.
Both 60 s derivatives are delivered as lossless 48 kHz/16-bit mono PCM.

Whether the supplied material obeys the split is a measurement, printed in full
by `--measure` and again before and after every filter. `fire` is not filtered:
it is the only voice on its own bus, it is never layered with anything, and a
fire's whole character is that it has both a low roar and a high crackle.
"""

import os
import struct
import sys
import wave

import aud
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SRC = os.path.join(PROJECT, "assets", "source", "audio", "ambience")
OUT = os.path.join(PROJECT, "assets", "audio", "ambience")

SOURCES = [
	"wind_low.wav",
	"wind_high.wav",
	"wind_mid.mp3",
	"winter_wind_in_trees_261226.wav",
	"snow_fall.mp3",
	"fire.mp3",
]

## Octave-ish bands. The three wind layers are supposed to live in different
## ones; the report is what says whether they do.
BANDS = [(20, 80), (80, 250), (250, 800), (800, 2500), (2500, 8000), (8000, 20000)]
BAND_NAMES = ["20-80", "80-250", ".25-.8k", ".8-2.5k", "2.5-8k", "8k+"]


def load_mono(path):
	"""Mono, because these are `AudioStreamPlayer3D` sources.

	A stereo bed handed to a positional player fights the panning that carries
	the wind's DIRECTION, which is half of what the bed is for -- the emitter
	sits upwind of the listener and swings round him as the heading veers. A
	recording with its own stereo image would smear that.
	"""
	sound = aud.Sound(path)
	data = sound.data()
	rate = int(sound.specs[0])
	if data.ndim > 1 and data.shape[1] > 1:
		left = data[:, 0].astype(np.float64)
		right = data[:, 1].astype(np.float64)
		correlation = float(np.corrcoef(left, right)[0, 1]) if len(left) > 1 else 1.0
		mono = data.mean(axis=1).astype(np.float64)
	else:
		mono = (data[:, 0] if data.ndim > 1 else data).astype(np.float64)
		correlation = 1.0
	return mono, rate, correlation


def db(value):
	return -120.0 if value <= 1e-12 else 20.0 * np.log10(value)


def rms(block):
	return 0.0 if len(block) == 0 else float(np.sqrt((block ** 2).mean()))


def band_shares(block, rate):
	nfft = 1 << int(np.ceil(np.log2(max(len(block), 2))))
	spec = np.abs(np.fft.rfft(block * np.hanning(len(block)), nfft)) ** 2
	freqs = np.fft.rfftfreq(nfft, 1.0 / rate)
	total = spec.sum() + 1e-20
	return [float(spec[(freqs >= lo) & (freqs < hi)].sum() / total) for lo, hi in BANDS]


def log_bands(block, rate, count=24):
	"""A coarse log-spaced spectrum, for comparing two passages. Coarse on
	purpose: two stretches of the same wind are never alike bin by bin, and a
	fine comparison would only be measuring the noise."""
	nfft = 1 << int(np.ceil(np.log2(max(len(block), 2))))
	spec = np.abs(np.fft.rfft(block * np.hanning(len(block)), nfft)) ** 2
	freqs = np.fft.rfftfreq(nfft, 1.0 / rate)
	edges = np.geomspace(30.0, min(18000.0, rate / 2.0 - 1.0), count + 1)
	out = np.empty(count)
	for i in range(count):
		mask = (freqs >= edges[i]) & (freqs < edges[i + 1])
		out[i] = spec[mask].sum() if mask.any() else 0.0
	return 10.0 * np.log10(out / (out.sum() + 1e-20) + 1e-12)


def measure(name, mono, rate, correlation):
	frames = len(mono)
	print("%-14s %8.4f s  %5d Hz  L/R r=%.4f  peak %.4f (%.1f dBFS)  rms %.1f dBFS  DC %+.5f" % (
		name, frames / rate, rate, correlation,
		float(np.abs(mono).max()), db(float(np.abs(mono).max())), db(rms(mono)),
		float(mono.mean())))
	shares = band_shares(mono, rate)
	print("               bands  " + "  ".join(
		"%s %5.1f%%" % (label, share * 100.0) for label, share in zip(BAND_NAMES, shares)))
	edge = int(0.25 * rate)
	print("               head %.1f dBFS   tail %.1f dBFS   quietest 0.25 s %.1f dBFS" % (
		db(rms(mono[:edge])), db(rms(mono[-edge:])),
		db(min(rms(mono[i:i + edge]) for i in range(0, frames - edge, edge)))))
	step = rate
	levels = [db(rms(mono[i:i + step])) for i in range(0, frames - step + 1, step)]
	print("               per-second dBFS: " + " ".join("%.0f" % v for v in levels))
	print("               level spread over the take: %.1f dB" % (
		max(levels) - min(levels) if levels else 0.0))
	return shares


def splice(mono, rate, segments):
	"""One or more passages of the same take, joined with equal-power fades.

	The owner's note invited it -- 可能需要你按段落截取或拼凑 -- and for a take that
	is mostly decay it is the only way to reach a usable length.
	"""
	fade = int(0.25 * rate)
	out = None
	for start, end, gain_db in segments:
		block = mono[int(start * rate):int(end * rate)] * (10.0 ** (gain_db / 20.0))
		if out is None:
			out = block.copy()
			continue
		n = min(fade, len(out), len(block))
		t = np.arange(n, dtype=np.float64) / float(n)
		out = np.concatenate([
			out[:-n],
			out[-n:] * np.cos(t * np.pi / 2.0) + block[:n] * np.sin(t * np.pi / 2.0),
			block[n:]])
	return out


def flatten_envelope(mono, rate, strength, window_s=0.30):
	"""Divide out the take's own slow level contour.

	`wind_low.wav` is not a bed. It is ONE gust with a 4.5 s decay, falling
	monotonically from -48 to -79 dBFS, and its second half measures 97% in
	250-800 Hz -- a ringing tail rather than air. Nothing steady can be cut from
	it as supplied: the head alone gives about 1.2 s.

	Flattening is legitimate here rather than a liberty, and the reason is the
	design. `AmbienceLayer` drives every layer's level from the wind system's own
	strength, so the FILE is meant to be a steady texture and the DYNAMICS are
	meant to arrive from outside it. A take with a 31 dB decay baked in fights
	its driver: the layer would fade out on its own schedule while the wind was
	still rising.

	It is safe on this material because these takes have no noise floor to speak
	of -- `wind_low.wav` measures -113 dBFS in its lead-in, so lifting its tail
	30 dB puts that floor at -83 dBFS, 60 dB under the material.

	`strength` 0 leaves the take alone and 1 makes it dead level. Partial values
	keep some internal movement, which is what `wind_high` wants: the fast
	octaves are the texture on a gust, not the gust.
	"""
	if strength <= 0.0:
		return mono
	window = max(1, int(window_s * rate))
	envelope = np.convolve(np.abs(mono), np.ones(window) / window, mode="same")
	reference = float(np.median(envelope)) + 1e-12
	# Floored, so a passage of near-silence is not multiplied up by a million.
	ratio = np.maximum(envelope / reference, 0.05)
	return mono / (ratio ** strength)


def best_loop(mono, rate, length_s, fade_s, coarse=0.005):
	"""Slide the start and score every candidate on how alike the two passages
	the crossfade will blend are.

	The score is level distance in dB plus a log-band spectral distance. A join
	between two passages that already match needs the least from the crossfade,
	and the crossfade is the part that can be heard.
	"""
	frames = len(mono)
	need = int(round((length_s + fade_s) * rate))
	fade = int(round(fade_s * rate))
	length = int(round(length_s * rate))
	if need >= frames:
		return None
	stride = max(1, int(round(coarse * rate)))
	best = None
	tried = 0
	for a in range(0, frames - need + 1, stride):
		tried += 1
		head = mono[a:a + fade]
		tail = mono[a + length:a + length + fade]
		level = abs(db(rms(head)) - db(rms(tail)))
		spectral = float(np.abs(log_bands(head, rate) - log_bands(tail, rate)).mean())
		score = level + spectral
		if best is None or score < best[0]:
			best = (score, a, level, spectral)
	return best + (tried,)


def crossfade_loop(mono, rate, start, length_s, fade_s):
	"""The standard crossfade loop, with a ramp law chosen from the material.

	`region` is one loop plus one crossfade. The extra crossfade at the end is
	the material that NATURALLY follows the loop point, so mixing it into the
	head is what makes the wrap continuous: coming off the last sample, what is
	heard first is the passage that really did come next, handing over to the
	head across the fade.

	THE RAMP LAW IS NOT A CONSTANT, and getting it wrong puts a 3 dB hole or a
	3 dB bump at the same place in every cycle -- as audible as the click it
	replaced, and harder to recognise.

	  * UNCORRELATED material -- two different stretches of wind -- adds in
	    POWER. Linear ramps would sum to 0.707 at the midpoint: a hole.
	    sin/cos ramps hold the power flat.
	  * CORRELATED material -- a narrow-band ring, which is exactly what
	    `wind_low.wav` becomes once it is band-limited to 250-900 Hz -- adds in
	    AMPLITUDE. sin/cos would sum to 1.414: a bump. Linear holds it flat.

	So the two laws are interpolated by the measured correlation between the two
	passages, and the coefficient is reported.
	"""
	length = int(round(length_s * rate))
	fade = int(round(fade_s * rate))
	region = mono[start:start + length + fade].copy()
	out = region[:length].copy()
	head = region[:fade]
	tail = region[length:length + fade]
	r = 0.0
	if fade > 1 and head.std() > 1e-12 and tail.std() > 1e-12:
		r = min(1.0, abs(float(np.corrcoef(head, tail)[0, 1])))
	t = np.arange(fade, dtype=np.float64) / float(fade)
	fade_in = (1.0 - r) * np.sin(t * np.pi / 2.0) + r * t
	fade_out = (1.0 - r) * np.cos(t * np.pi / 2.0) + r * (1.0 - t)
	out[:fade] = tail * fade_out + head * fade_in
	return out, r


def circular_filter(loop, rate, high_pass=0.0, low_pass=0.0, slope_octaves=1.0):
	"""Band-limit WITHOUT disturbing the join.

	An FFT filter is a circular convolution: it treats the signal as already
	periodic, so whatever it does at the end it does identically at the start.
	A time-domain FIR would smear across the loop point and undo the search that
	placed it.

	The skirts are cosine ramps over `slope_octaves` rather than brick walls. A
	brick wall in the frequency domain is a sinc in time, and it rings.

	DC is zeroed unconditionally, filter or no filter: an offset is a step at
	every wrap, which is the one click a crossfade cannot hide.
	"""
	n = len(loop)
	spec = np.fft.rfft(loop)
	freqs = np.fft.rfftfreq(n, 1.0 / rate)
	gain = np.ones_like(freqs)
	safe = np.maximum(freqs, 1e-6)
	if high_pass > 0.0:
		ramp = np.clip(np.log2(safe / (high_pass / (2.0 ** slope_octaves))) / slope_octaves, 0.0, 1.0)
		gain *= 0.5 - 0.5 * np.cos(ramp * np.pi)
	if low_pass > 0.0:
		ramp = np.clip(np.log2((low_pass * (2.0 ** slope_octaves)) / safe) / slope_octaves, 0.0, 1.0)
		gain *= 0.5 - 0.5 * np.cos(ramp * np.pi)
	gain[0] = 0.0
	return np.fft.irfft(spec * gain, n)


def circular_notches(loop, rate, notches, depth_fraction=1.0):
	"""Remove stable tonal lines without changing the loop join.

	Each notch is (centre Hz, FWHM Hz, total attenuation dB). The filter runs
	once before loop search and once after the crossfade, so each pass applies
	half the requested depth. Gaussian skirts keep the affected bandwidth tiny
	and avoid the hollow sound of a full harmonic comb.
	"""
	if not notches:
		return loop
	n = len(loop)
	spec = np.fft.rfft(loop)
	freqs = np.fft.rfftfreq(n, 1.0 / rate)
	gain = np.ones_like(freqs)
	for centre, width, depth_db in notches:
		sigma = max(float(width) / 2.354820045, 1e-6)
		shape = np.exp(-0.5 * ((freqs - float(centre)) / sigma) ** 2)
		centre_gain = 10.0 ** (-float(depth_db) * depth_fraction / 20.0)
		gain *= 1.0 - (1.0 - centre_gain) * shape
	return np.fft.irfft(spec * gain, n)


def k_weight(freqs, rate):
	"""ITU-R BS.1770's K-weighting, as a magnitude response on an FFT grid.

	Two RBJ biquads evaluated analytically -- a +4 dB high shelf at 1681.97 Hz
	and a 2nd-order high-pass at 38.14 Hz. Those are the analog prototypes the
	published 48 kHz coefficients are derived from, so deriving them here works
	at 22.05 and 44.1 kHz too, which the tabulated coefficients do not.
	"""
	def biquad(b0, b1, b2, a0, a1, a2):
		w = 2.0 * np.pi * freqs / rate
		z1 = np.exp(-1j * w)
		z2 = z1 * z1
		return np.abs((b0 + b1 * z1 + b2 * z2) / (a0 + a1 * z1 + a2 * z2))

	# High shelf, f0 = 1681.974 Hz, gain +3.99984 dB, Q = 0.70718
	amp = 10.0 ** (3.999843853973347 / 40.0)
	w0 = 2.0 * np.pi * 1681.974450955533 / rate
	alpha = np.sin(w0) / (2.0 * 0.7071752369554196)
	cos0 = np.cos(w0)
	two_sqrt_a_alpha = 2.0 * np.sqrt(amp) * alpha
	shelf = biquad(
		amp * ((amp + 1.0) + (amp - 1.0) * cos0 + two_sqrt_a_alpha),
		-2.0 * amp * ((amp - 1.0) + (amp + 1.0) * cos0),
		amp * ((amp + 1.0) + (amp - 1.0) * cos0 - two_sqrt_a_alpha),
		(amp + 1.0) - (amp - 1.0) * cos0 + two_sqrt_a_alpha,
		2.0 * ((amp - 1.0) - (amp + 1.0) * cos0),
		(amp + 1.0) - (amp - 1.0) * cos0 - two_sqrt_a_alpha)

	# High-pass, f0 = 38.135 Hz, Q = 0.50033
	w0 = 2.0 * np.pi * 38.13547087602444 / rate
	alpha = np.sin(w0) / (2.0 * 0.5003270373238773)
	cos0 = np.cos(w0)
	high_pass = biquad(
		(1.0 + cos0) / 2.0, -(1.0 + cos0), (1.0 + cos0) / 2.0,
		1.0 + alpha, -2.0 * cos0, 1.0 - alpha)
	return shelf * high_pass


def loudness_lufs(loop, rate):
	"""BS.1770 loudness, in LUFS.

	EQUAL RMS IS NOT EQUAL LOUDNESS, and on this set the difference decides
	whether the mix works at all. `wind_low` carries 81% of its energy under
	250 Hz and `wind_high` carries 96% of its between 0.8 and 2.5 kHz -- where
	the ear is at its most sensitive. Levelled by RMS they are perceptually far
	apart, so the layer that plays 78% of the time and carries the world alone
	during a threat would sit under a hiss that plays 5% of the time.

	Measured here rather than corrected here: the correction belongs in
	`AmbienceMap`'s per-layer `gain_db`, which is a `.tres` field the owner can
	re-tune by ear without anybody re-rendering a file. The material stays what
	it is; the mix stays data.
	"""
	spec = np.abs(np.fft.rfft(loop)) ** 2
	freqs = np.fft.rfftfreq(len(loop), 1.0 / rate)
	weighted = spec * (k_weight(freqs, rate) ** 2)
	n = len(loop)
	doubled = weighted.copy()
	doubled[1:-1] *= 2.0
	mean_square = doubled.sum() / float(n * n)
	return -0.691 + 10.0 * np.log10(mean_square + 1e-20)


def normalise(loop, target_rms_db, ceiling_db=-1.0):
	"""To a common RMS, not to a common peak.

	The five takes span 24 dB of RMS as supplied -- `wind_low.wav` at -55 dBFS
	against `wind_high.wav` at -31 -- and `AmbienceMap`'s per-layer `gain_db` was
	authored blind, as a MIX decision. It can only mean anything if the files it
	mixes are comparable to begin with.

	Peak normalisation would not do it: for noise-like material the peak is one
	sample of luck, and matching on it leaves the perceived levels 10 dB apart.
	"""
	current = rms(loop)
	if current <= 0.0:
		return loop, 0.0
	gain = (10.0 ** (target_rms_db / 20.0)) / current
	peak = float(np.abs(loop).max()) * gain
	ceiling = 10.0 ** (ceiling_db / 20.0)
	if peak > ceiling:
		gain *= ceiling / peak
	return loop * gain, db(gain)


def join_report(loop, rate, label):
	"""Whether the join can be heard, as a number rather than as a hope.

	The test is not "is the step small" -- inside any noise signal adjacent
	samples differ constantly. It is whether the step ACROSS THE WRAP is
	ORDINARY, measured against the take's own distribution of adjacent-sample
	differences. A wrap under the 99.9th percentile of the signal's own motion is
	indistinguishable from the signal.

	The level either side is reported too, because that is where a linear
	crossfade's 3 dB hole would show up.
	"""
	deltas = np.abs(np.diff(loop))
	wrap = abs(float(loop[0] - loop[-1]))
	p999 = float(np.percentile(deltas, 99.9))
	median = float(np.median(deltas))
	clean = wrap <= p999
	print("%s wrap step %.6f | median %.6f | p99.9 %.6f  -> %s" % (
		label, wrap, median, p999,
		"CLEAN (under the signal's own motion)" if clean else "AUDIBLE (above p99.9)"))

	# LEVEL CONTINUITY, by the same logic one scale up. A wrap with no sample
	# step can still breathe -- a crossfade whose ramp law is wrong for the
	# material puts a hole or a bump once per cycle, and a single before/after
	# reading of a bursty signal cannot tell that from the signal's own motion.
	#
	# So: play the loop twice, take a sliding 100 ms level, and compare the
	# change across the wrap against the distribution of every other change in
	# the file. The question is never "is it small", always "is it ordinary".
	window = max(1, int(0.10 * rate))
	hop = max(1, int(0.025 * rate))
	doubled = np.concatenate([loop, loop])
	levels = np.array([db(rms(doubled[i:i + window]))
		for i in range(0, len(doubled) - window, hop)])
	swings = np.abs(np.diff(levels))
	wrap_index = int((len(loop) - window // 2) / hop)
	span = max(1, window // hop)
	local = float(np.abs(levels[max(0, wrap_index - span)] - levels[min(len(levels) - 1, wrap_index + span)]))
	p95 = float(np.percentile(swings, 95))
	steady = local <= max(p95 * span, 1.5)
	print("%s level across the wrap %+.1f dB | the loop's own 100 ms swings: median %.1f, p95 %.1f dB  -> %s" % (
		label, local, float(np.median(swings)), p95,
		"ORDINARY" if steady else "BREATHES -- the ramp law is wrong for this material"))
	return clean and steady


def write_wav(path, samples, rate):
	"""16-bit mono PCM, uncompressed.

	NOT QOA, which this project's one-shots use. QOA is lossy and block-based,
	and its encoder does not know the signal wraps -- so the one sample junction
	the whole file exists to protect is the one place the codec is free to guess.
	Uncompressed is a few megabytes and a guarantee.
	"""
	ints = np.round(np.clip(samples, -1.0, 1.0) * 32767.0).astype(np.int16)
	with wave.open(path, "wb") as handle:
		handle.setnchannels(1)
		handle.setsampwidth(2)
		handle.setframerate(rate)
		handle.writeframes(ints.tobytes())


# layer, source, segments [(start s, end s, gain dB)], flatten, loop s, fade s,
# high-pass Hz, low-pass Hz, notches [(centre Hz, FWHM Hz, attenuation dB)],
# target RMS dBFS, why
#
# THE ASSIGNMENT IS BY MEASUREMENT, NOT BY FILENAME -- see the header.
CUTS = [
	("wind_low", "winter_wind_in_trees_261226.wav", [(80.00, 152.80, 0.0)], 0.0, 60.0, 10.0, 35.0, 900.0,
	 [(60.5, 8.0, 36.0), (124.0, 7.0, 18.0), (184.5, 16.0, 14.0),
	  (248.0, 6.0, 10.0), (496.0, 10.0, 8.0), (558.0, 10.0, 8.0)], -20.0,
	 "The always-on air bed. A later passage than wind_mid, with mains-like tones removed and no breathing envelope."),
	("wind_mid", "winter_wind_in_trees_261226.wav", [(0.50, 71.10, 0.0)], 0.0, 60.0, 10.0, 200.0, 2500.0,
	 [(185.5, 4.0, 12.0), (247.0, 3.0, 12.0), (370.5, 14.0, 10.0),
	  (432.0, 3.0, 6.0), (494.0, 5.0, 10.0), (555.0, 5.0, 8.0)], -20.0,
	 "The gust layer. An early passage kept separate from wind_low, with the old take's 500 Hz ring absent."),
	("wind_high", "wind_high.wav", [(0.30, 6.10, 0.0)], 0.6, 4.6, 0.7, 700.0, 0.0, [], -20.0,
	 "86% in 0.8-2.5 kHz, the top of the three. Partly flattened: 36 dB of its own gusts would fight the driver."),
	("snow_fall", "snow_fall.mp3", [(0.30, 6.80, 0.0)], 0.0, 5.4, 0.9, 700.0, 0.0, [], -20.0,
	 "Steady within 4 dB, but 56% of it is wind under 250 Hz -- high-passed off, or the wind is heard twice."),
	("fire", "fire.mp3", [(0.50, 14.30, 0.0)], 0.0, 12.0, 1.3, 0.0, 0.0, [], -20.0,
	 "Steady within 4 dB across the take and NO transient above 6x the median envelope -- nothing to mark the loop."),
]


def build(layer, source, segments, flatten, length_s, fade_s, high_pass, low_pass,
          notches, target_rms_db, why, mono, rate):
	print("-" * 78)
	print("%s  <-  %s" % (layer, source))
	print("  %s" % why)
	piece = splice(mono, rate, segments)
	raw_shares = band_shares(piece, rate)
	before = [db(rms(piece[i:i + rate])) for i in range(0, len(piece) - rate + 1, rate)]
	piece = flatten_envelope(piece, rate, flatten)
	after = [db(rms(piece[i:i + rate])) for i in range(0, len(piece) - rate + 1, rate)]
	if flatten > 0.0 and before:
		print("  flatten %.2f: level spread %.1f dB -> %.1f dB" % (
			flatten, max(before) - min(before), max(after) - min(after)))

	# BAND-LIMITED BEFORE THE SEARCH, not after. Scored on the raw segment, the
	# spectral distance is dominated by bands the filter is about to delete --
	# `wind_mid` scored 7.65 dB that way, almost all of it in the 20-80 Hz and
	# 0.8-2.5 kHz regions that do not survive to the file. The search has to see
	# what ships.
	if high_pass > 0.0 or low_pass > 0.0:
		piece = circular_filter(piece, rate, high_pass, low_pass)
	if notches:
		piece = circular_notches(piece, rate, notches, 0.5)
	found = best_loop(piece, rate, length_s, fade_s)
	if found is None:
		print("  REFUSED: %.2f s of material cannot carry a %.2f s loop plus a %.2f s crossfade" % (
			len(piece) / rate, length_s, fade_s))
		return None
	_score, start, level, spectral, tried = found
	print("  loop start %.3f s into the segment, best of %d candidates: level match %.2f dB, spectral distance %.2f dB" % (
		start / rate, tried, level, spectral))

	loop, correlation = crossfade_loop(piece, rate, start, length_s, fade_s)
	print("  crossfade %.2f s, passages correlate r=%.3f -> %s ramp" % (
		fade_s, correlation,
		"equal-power" if correlation < 0.25 else
		("linear" if correlation > 0.75 else "%.0f%% of the way from equal-power to linear" % (correlation * 100))))
	# Applied again, and circularly this time: the pre-search filter was on an
	# open segment, and only a circular pass can leave the wrap alone.
	loop = circular_filter(loop, rate, high_pass, low_pass)
	if notches:
		loop = circular_notches(loop, rate, notches, 0.5)
	if high_pass > 0.0 or low_pass > 0.0:
		print("  filter: %s%s(circular, so the join is untouched)" % (
			"high-pass %.0f Hz " % high_pass if high_pass > 0 else "",
			"low-pass %.0f Hz " % low_pass if low_pass > 0 else ""))
		print("    source " + " ".join("%s %4.1f%%" % (l, s * 100)
			for l, s in zip(BAND_NAMES, raw_shares)))
		print("    loop   " + " ".join("%s %4.1f%%" % (l, s * 100)
			for l, s in zip(BAND_NAMES, band_shares(loop, rate))))
	else:
		print("  filter: none beyond DC removal")
		print("    bands  " + " ".join("%s %4.1f%%" % (l, s * 100)
			for l, s in zip(BAND_NAMES, band_shares(loop, rate))))
	if notches:
		print("  notches: " + ", ".join("%.1f Hz/%.1f Hz/%g dB" % notch for notch in notches))

	loop, applied = normalise(loop, target_rms_db)
	lufs = loudness_lufs(loop, rate)
	print("  normalised %+.1f dB to %.0f dBFS RMS; peak now %.1f dBFS; LOUDNESS %.1f LUFS (%+.1f vs RMS)" % (
		applied, target_rms_db, db(float(np.abs(loop).max())), lufs, lufs - target_rms_db))
	clean = join_report(loop, rate, "  join:")
	print("  LOOP %.3f s at %d Hz = %d frames, %.2f MB as 16-bit mono PCM" % (
		len(loop) / rate, rate, len(loop), len(loop) * 2 / 1048576.0))
	return loop, rate, clean


def main():
	only = None
	if "--only" in sys.argv:
		index = sys.argv.index("--only")
		if index + 1 >= len(sys.argv):
			raise ValueError("--only requires a layer id")
		only = sys.argv[index + 1]
		known = [cut[0] for cut in CUTS]
		if only not in known:
			raise ValueError("unknown layer %r; expected one of %s" % (only, ", ".join(known)))

	print("=" * 78)
	print("SUPPLIED MATERIAL")
	print("=" * 78)
	loaded = {}
	for name in SOURCES:
		mono, rate, correlation = load_mono(os.path.join(SRC, name))
		loaded[name] = (mono, rate)
		measure(name, mono, rate, correlation)
		print()
	if "--measure" in sys.argv:
		return

	print("=" * 78)
	print("LOOPS")
	print("=" * 78)
	os.makedirs(OUT, exist_ok=True)
	measured = {}
	for layer, source, segments, flatten, length_s, fade_s, hp, lp, notches, target, why in CUTS:
		if only is not None and layer != only:
			continue
		mono, rate = loaded[source]
		built = build(layer, source, segments, flatten, length_s, fade_s, hp, lp, notches, target, why,
			mono, rate)
		if built is None:
			continue
		loop, rate, clean = built
		measured[layer] = loudness_lufs(loop, rate)
		if not clean:
			print("  NOT WRITTEN -- a layer that clicks is worse than a layer that is absent")
			print()
			continue
		path = os.path.join(OUT, layer + ".wav")
		write_wav(path, loop, rate)
		print("  -> %s" % path)
		print()

	# What `tools/generate_ambience.gd` needs in order to mix these. Every file
	# leaves here at the same RMS, so the difference below is purely how the ear
	# weights where each one sits -- and it is the number the authored gain_db
	# has to carry, because nobody on this end can hear it.
	print("=" * 78)
	print("PERCEIVED LOUDNESS AT EQUAL RMS -- the correction gain_db owes")
	print("=" * 78)
	if measured:
		reference = max(measured.values())
		for layer in [cut[0] for cut in CUTS]:
			if layer in measured:
				print("  %-10s %7.1f LUFS   correction %+5.1f dB" % (
					layer, measured[layer], reference - measured[layer]))
		print("  (relative to %s, the loudest at equal RMS)" % max(measured, key=measured.get))


if __name__ == "__main__":
	main()
