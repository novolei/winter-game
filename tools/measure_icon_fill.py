"""Can this icon carry a liquid level?

    python tools/measure_icon_fill.py [--sheet <dir>]

The dog's concern readout (src/entities/wildlife/concern_readout.gd) cuts a stat
icon's silhouette at a horizontal line: `scrim/veil` below it, `ink/muted` above,
both opaque. The silhouette is the bottle and the line is the liquid.

That works for a shape the eye reads as a VESSEL and fails for one it does not,
and the failure is silent -- the icon still renders, still shows two tones, and
still changes when the stat changes. It just stops meaning "how full". So the
property is measured here rather than judged, on three numbers:

  CHORD   the silhouette's horizontal span at the cut, as a share of the icon's
          own width. This is the length of the waterline. Below about a third
          the cut reads as a nick in the outline rather than as a level.

  ON INK  the share of displayed fills whose cut row actually lands on ink. An
          icon built from detached pieces -- a bowl above its foot, a hand above
          its cuff -- has gaps, and in a gap there is no line to see at all.

  DEAD    the widest run of fill where the filled AREA moves less than 2% of the
          icon's ink. Inside a dead run two different stat values draw the same
          picture, and the reading is a lie for that stretch of its range.

Only the fills the readout can actually DISPLAY are measured. It appears when a
stat is below the highest threshold authored in data/stats/*.tres (0.50), so the
range is 0.00 .. 0.50 and an icon that only reads when nearly full has not been
given a pass by choosing a kind range.

Needs Pillow. Prints a table; --sheet also writes the contact sheet the verdict
was read off, because a number about a picture has to be checked against the
picture (briefing, "正确的测量，回答错误的问题").
"""
import sys

from PIL import Image

ICON_DIR = "assets/ui/icons"
GLYPHS = ["core_temperature", "hunger", "thirst", "fatigue",
          "frostbite_hands", "frostbite_feet"]

# The range the readout displays. See the module docstring.
FILL_LOW, FILL_HIGH, FILL_STEP = 0.00, 0.50, 0.025

# data/palette/color_bible.tres. Written here rather than read because this is a
# tool, and tools/ is the one place briefing constraint 6 exempts -- it is the
# side of the fence the generators live on.
FILLED = (19, 28, 48)        # structure_tones[3]  scrim/veil
EMPTY = (93, 123, 166)       # snow_tones[4]       ink/muted
SNOW = (143, 176, 216)       # snow_tones[0]       the acceptance background

# Measured on a saved frame: the cel pass writes the palette value straight into
# DIFFUSE_LIGHT with ALBEDO = vec3(1.0), and what reaches the PNG is a flat 1.155
# gain on all three channels (briefing trap 7, and the dog wave's section 7.2).
GAIN = 1.155

# Where the verdicts sit. Both come from the contact sheet this tool writes, not
# from taste: at a chord below 0.30 the flame's tip and the bolt's tail are the
# same picture, and a dead run of 0.10 is a fifth of the displayed range.
MIN_CHORD = 0.30
MAX_DEAD = 0.10


def screen(rgb):
    return tuple(min(255, round(c * GAIN)) for c in rgb)


def alpha_of(name):
    return Image.open("%s/%s.png" % (ICON_DIR, name)).convert("RGBA").split()[3]


def rows_of(alpha):
    """Per row: (first ink x, last ink x, ink count). Absent rows have none."""
    w, h = alpha.size
    px = alpha.load()
    out = {}
    for y in range(h):
        run = [x for x in range(w) if px[x, y] > 10]
        if run:
            out[y] = (run[0], run[-1], len(run))
    return out


def fills():
    f = FILL_LOW
    while f <= FILL_HIGH + 1e-9:
        yield round(f, 4)
        f += FILL_STEP


def measure(name):
    alpha = alpha_of(name)
    rows = rows_of(alpha)
    ys = sorted(rows)
    y0, y1 = ys[0], ys[-1]
    x0 = min(rows[y][0] for y in ys)
    x1 = max(rows[y][1] for y in ys)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    total = sum(rows[y][2] for y in ys)

    steps = list(fills())
    chords, gaps, areas = [], 0, []
    for f in steps:
        # The line runs from the bottom of the INK to the top of it, not from
        # the bottom of the canvas: hunger's bowl occupies 86 of 256 rows and a
        # canvas-relative cut would read 0.50 as a full bowl.
        cut = (y1 + 1) - f * bh
        row = min(y1, max(y0, int(cut)))
        if row in rows:
            l, r, _ = rows[row]
            # Measured only where there IS a line. A cut that lands in a gap has
            # no chord at all, which is a different fault and is counted as one.
            if f > 0.0:
                chords.append((r - l + 1) / bw)
        else:
            gaps += 1
        areas.append(sum(rows[y][2] for y in ys if y >= cut) / max(total, 1))

    # The WIDEST WINDOW over which the filled area barely moves, not a run of
    # small steps: twenty consecutive 1% steps are a 20% change and read fine,
    # while one 0.15-wide stretch that moves 1% in total is a stat the icon
    # cannot report. Written the accumulating way first, which called the flame
    # dead for 0.15 of its range and the flame is not dead.
    dead = 0.0
    for i in range(len(areas)):
        j = i
        while j + 1 < len(areas) and areas[j + 1] - areas[i] < 0.02:
            j += 1
        dead = max(dead, steps[j] - steps[i])
    return {
        "name": name, "w": bw, "h": bh, "aspect": bw / bh,
        "chord_min": min(chords), "chord_mean": sum(chords) / len(chords),
        "on_ink": 1.0 - gaps / len(steps), "dead": dead,
    }


def sheet(path, size=44):
    """The picture the numbers are about, over the acceptance background."""
    shown = [0.05, 0.15, 0.25, 0.35, 0.50]
    pad = 10
    cell = size + pad * 2
    board = Image.new("RGB", (cell * len(shown), cell * len(GLYPHS)), screen(SNOW))
    for r, name in enumerate(GLYPHS):
        a = alpha_of(name)
        rows = rows_of(a)
        ys = sorted(rows)
        y0, y1 = ys[0], ys[-1]
        gx0 = min(rows[y][0] for y in ys)
        gx1 = max(rows[y][1] for y in ys)
        crop = a.crop((gx0, y0, gx1 + 1, y1 + 1))
        k = size / max(crop.width, crop.height)
        tw, th = max(1, round(crop.width * k)), max(1, round(crop.height * k))
        m = crop.resize((tw, th), Image.LANCZOS)
        for c, f in enumerate(shown):
            line = th - f * th
            lo, hi = m.copy(), m.copy()
            lp, hp = lo.load(), hi.load()
            for y in range(th):
                for x in range(tw):
                    if y < line:
                        lp[x, y] = 0
                    else:
                        hp[x, y] = 0
            g = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
            g.paste(EMPTY + (255,), (0, 0), hi)
            g.paste(FILLED + (255,), (0, 0), lo)
            board.paste(g, (c * cell + (cell - tw) // 2,
                            r * cell + (cell - th) // 2), g)
    board = board.resize((board.width * 2, board.height * 2), Image.NEAREST)
    board.save(path)
    print("wrote %s  (%d px glyphs, fills %s, over lit snow)"
          % (path, size, " ".join("%.2f" % f for f in shown)))


def main():
    out = None
    if "--sheet" in sys.argv:
        out = sys.argv[sys.argv.index("--sheet") + 1]
    print("fills %.2f .. %.2f step %.3f   chord floor %.2f   dead ceiling %.2f\n"
          % (FILL_LOW, FILL_HIGH, FILL_STEP, MIN_CHORD, MAX_DEAD))
    print("%-18s %9s %6s %7s %7s %6s %6s  %s"
          % ("glyph", "ink box", "aspect", "chord-", "chord~", "on-ink", "dead", "verdict"))
    bad = 0
    for name in GLYPHS:
        m = measure(name)
        fail = []
        if m["chord_min"] < MIN_CHORD:
            fail.append("chord %.2f < %.2f" % (m["chord_min"], MIN_CHORD))
        if m["dead"] > MAX_DEAD + 1e-9:
            fail.append("dead run %.3f > %.2f" % (m["dead"], MAX_DEAD))
        if m["on_ink"] < 1.0:
            fail.append("cut misses ink on %.0f%% of fills" % (100 * (1 - m["on_ink"])))
        bad += 1 if fail else 0
        print("%-18s %4dx%-4d %6.2f %7.2f %7.2f %5.0f%% %6.3f  %s"
              % (name, m["w"], m["h"], m["aspect"], m["chord_min"], m["chord_mean"],
                 100 * m["on_ink"], m["dead"],
                 "READS" if not fail else "; ".join(fail)))
    if out:
        print()
        sheet(out.rstrip("/") + "/icon-fill.png")
    print("\n%d of %d glyphs carry a level." % (len(GLYPHS) - bad, len(GLYPHS)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
