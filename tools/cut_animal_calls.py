"""Cut the owner's two supplied wildlife takes into individual calls.

    "D:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background \
        --factory-startup --python tools/cut_animal_calls.py

---------------------------------------------------------------------------
WHY THIS RUNS UNDER BLENDER AND NOT UNDER GODOT
---------------------------------------------------------------------------
Constraint 7 says generated content is written by a script in `tools/` rather
than by hand, and that is what this is -- but it cannot be a `.gd` script.
Godot can LOAD an `.mp3` and tell you its length; it exposes no way to read the
decoded samples back out, so it cannot measure a call, find a boundary or write
a slice. `ffmpeg` is not installed on this machine and the system Python has no
numpy.

Blender ships both audaspace (`aud`, which decodes mp3) and numpy, so Blender's
bundled Python is the only decoder available here. `tools/decimate_character.py`
is the same shape.

---------------------------------------------------------------------------
WHAT IS ACTUALLY IN THE TWO FILES -- MEASURED, NOT GUESSED
---------------------------------------------------------------------------
Both are 44100 Hz stereo mp3.

`crow_raw.mp3`  2.0434 s.  THREE caws, digital silence before the first
                (0.3047 s) and after the last (0.0407 s), reverb tail between
                them. L and R correlate at 1.0000 -- it is dual mono in a
                stereo container, so the downmix below is lossless.

                  1  0.354-0.609 s  peak 0.501  dominant 1157 Hz
                  2  0.953-1.182 s  peak 0.477  dominant 1198 Hz
                  3  1.472-1.736 s  peak 0.317  dominant 1209 Hz

                The third is 4 dB quieter and has a third of the first's
                energy above 3 kHz. It is the same bird further away, which is
                exactly the "one already distant" the startle brief's rhythm
                ends on -- so it is kept as its own file rather than levelled.

`dog_raw.mp3`   5.7379 s.  Room tone throughout at -39.4 dBFS, no digital
                silence anywhere. L/R correlate at 0.9644; the mono downmix
                costs 0.7 dB of RMS and no cancellation. Eleven events:

                  0.05-0.23  soft, 62% of energy in 250-800 Hz   huff
                  0.42-0.68  soft, 83% in 250-800, slow rise     WHIMPER
                  0.78-1.05  93% in 800-2000 Hz, sharp attack    BARK
                  1.10-1.50  97% in 800-2000, periodicity 0.94   WHINE
                  1.62-1.80  70% in 800-2000 + 30% above 2 kHz   BARK
                  1.80-2.05  98% in 800-2000, periodicity 0.96   whine tail
                  2.36-2.72  91% in 800-2000, loudest (0.524)    BARK
                  2.84-3.06  79% in 250-800, sharp attack        yelp
                  3.26-3.52  59% 250-800 + 28% 800-2000          WHINE
                  3.62-3.97  32% 250-800 + 50% 800-2000          WHINE
                  4.03-4.52  87% in 250-800, periodicity 0.89    WHIMPER
                  4.55-5.35  53% below 60 Hz + 30% above 2 kHz   breath, room

THERE IS NO GROWL IN THIS FILE. That is the finding the dog task turns on, so
it was measured rather than judged by ear-substitute: a growl is a low
phonation with its fundamental at 50-200 Hz, and the 60-250 Hz band NEVER rises
more than 10.5 dB above its own floor anywhere in the take, against 41.1 dB for
the barks in 800-2000 Hz. What low-frequency energy the file has sits at
31-47 Hz and is present at the same level in the silent tail -- it is mic and
room rumble, not an animal.

---------------------------------------------------------------------------
WHAT THIS SCRIPT DOES *NOT* DO, AND WHY
---------------------------------------------------------------------------
No normalising. The third caw is quieter than the first two and the whimpers
are quieter than the barks; that difference is the material, and a `.tres`
carries `gain_db` per call for anything that wants to override it.

No high-pass, though the dog's 31-47 Hz rumble is a real defect and would come
off cleanly (every vocalisation is above 250 Hz). Filtering changes a supplied
asset in a way nobody on this end can verify by listening, and the rumble is
40 dB down and below what a player's speakers reproduce. Measured and reported
instead of quietly applied.

No trimming of the dog's room tone, for the same reason: gating it would make
each slice start and stop dead, which is more audible than the tone itself.
"""

import os
import struct
import wave

import aud
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SRC = os.path.join(PROJECT, "assets", "source", "audio", "wildlife")
OUT = os.path.join(PROJECT, "assets", "audio", "wildlife")

# (source, out folder, name, start s, end s, fade-in ms, fade-out ms, why)
#
# Boundaries sit in the measured quiet between events, not on the event edges,
# so each slice carries its own attack and its own decay. The long fade-outs
# are the two slices that end while the animal is still making a sound:
# `dog_bark_02` runs straight into a whine at 1.80 and `dog_whine_01` is still
# sounding at 1.50.
CUTS = [
	("crow_raw.mp3", "crow", "crow_caw_01", 0.300, 0.920, 3.0, 25.0,
	 "the nearest caw; loudest and brightest of the three"),
	("crow_raw.mp3", "crow", "crow_caw_02", 0.920, 1.440, 3.0, 25.0,
	 "the answer, 0.6 s later and a touch lower"),
	("crow_raw.mp3", "crow", "crow_caw_03", 1.440, 2.010, 3.0, 30.0,
	 "4 dB down with a third the energy above 3 kHz -- the bird already distant"),

	("dog_raw.mp3", "dog", "dog_bark_01", 0.745, 1.100, 5.0, 30.0,
	 "93% of its energy in 800-2000 Hz; the first clean bark"),
	("dog_raw.mp3", "dog", "dog_bark_02", 1.585, 1.820, 5.0, 45.0,
	 "the brightest -- 30% above 2 kHz -- and the one that runs into a whine"),
	("dog_raw.mp3", "dog", "dog_bark_03", 2.325, 2.790, 5.0, 35.0,
	 "loudest event in the take (0.524) and the only one isolated on both sides"),

	("dog_raw.mp3", "dog", "dog_whine_01", 1.100, 1.555, 8.0, 60.0,
	 "sustained 848 Hz, periodicity 0.94; the loud insistent whine"),
	("dog_raw.mp3", "dog", "dog_whine_02", 3.230, 3.570, 8.0, 45.0,
	 "softer, 723 Hz, falling"),
	("dog_raw.mp3", "dog", "dog_whine_03", 3.585, 3.970, 8.0, 45.0,
	 "softer still, 848 Hz"),

	("dog_raw.mp3", "dog", "dog_whimper_01", 0.415, 0.690, 10.0, 50.0,
	 "quiet (peak 0.139), 649 Hz, slow rise and fall -- no attack at all"),
	("dog_raw.mp3", "dog", "dog_whimper_02", 3.970, 4.560, 10.0, 60.0,
	 "0.59 s, 668 Hz falling, periodicity 0.89 -- the injured-dog sound"),
]


def load_mono(path):
	sound = aud.Sound(path)
	data = sound.data()
	rate = int(sound.specs[0])
	mono = data.mean(axis=1) if data.ndim > 1 else data
	return mono.astype(np.float64), rate


def rms(block):
	if len(block) == 0:
		return 0.0
	return float(np.sqrt((block ** 2).mean()))


def write_wav(path, samples, rate):
	"""16-bit mono PCM. Godot imports this with no decode cost and no format
	negotiation, which is what a one-shot under 0.6 s wants."""
	clipped = np.clip(samples, -1.0, 1.0)
	ints = np.round(clipped * 32767.0).astype(np.int16)
	with wave.open(path, "wb") as handle:
		handle.setnchannels(1)
		handle.setsampwidth(2)
		handle.setframerate(rate)
		handle.writeframes(struct.pack("<%dh" % len(ints), *ints.tolist()))


def main():
	sources = {}
	for name in sorted({cut[0] for cut in CUTS}):
		sources[name] = load_mono(os.path.join(SRC, name))
		mono, rate = sources[name]
		print("%s: %d frames at %d Hz = %.4f s" % (name, len(mono), rate, len(mono) / rate))

	print()
	print("%-16s %8s %8s %7s %8s %8s %8s" %
	      ("file", "start", "end", "len", "peak", "rms", "edge rms"))
	for source, folder, name, t0, t1, fade_in_ms, fade_out_ms, _why in CUTS:
		mono, rate = sources[source]
		a = int(round(t0 * rate))
		b = min(len(mono), int(round(t1 * rate)))
		slice_ = mono[a:b].copy()

		# The boundary is only a good boundary if it is quiet. Printed so the
		# claim is checkable rather than asserted in a comment.
		edge = max(rms(mono[max(0, a - int(0.005 * rate)):a]),
		           rms(mono[b:b + int(0.005 * rate)]))

		fade_in = max(1, int(fade_in_ms * rate / 1000.0))
		fade_out = max(1, int(fade_out_ms * rate / 1000.0))
		if fade_in + fade_out < len(slice_):
			slice_[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
			slice_[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)

		folder_path = os.path.join(OUT, folder)
		os.makedirs(folder_path, exist_ok=True)
		out_path = os.path.join(folder_path, name + ".wav")
		write_wav(out_path, slice_, rate)
		print("%-16s %8.3f %8.3f %7.3f %8.4f %8.5f %8.5f" %
		      (name, t0, t1, (b - a) / float(rate),
		       float(np.abs(slice_).max()), rms(slice_), edge))

	print()
	print("wrote %d file(s) under %s" % (len(CUTS), OUT))


main()
