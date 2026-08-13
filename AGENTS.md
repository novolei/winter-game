# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project state

WinterTime is a Godot 4.7 winter survival game. **Wave 0 (framework foundation) is complete**: 98 passing tests, three autoloads (`EventBus`, `ServiceRegistry`, `WorldClock`), a game-agnostic core under `src/core/`, nine `Resource` definition classes, three static-analysis art gates, and a headless test harness. No scenes or assets exist yet, and no main scene is set — Wave 1 starts the world.

### Read these first

**Before writing code**, in this order:

1. [Docs/AGENT-BRIEFING.md](Docs/AGENT-BRIEFING.md) — **the operational file.** Environment, the commands, eight binding constraints, and six engine traps this project has already paid to discover. Reading it saves a debugging cycle per trap.
2. [Docs/DEFERRED.md](Docs/DEFERRED.md) — every accepted-but-unfixed finding, with the wave that owns it. **Wave 1 opens with seven blockers**, all one defect class: the art gates cannot see the model formats the asset pipeline actually produces.
3. The design docs, which are the source of truth for architecture, naming, and art rules:
   - [GDD](Docs/superpowers/specs/2026-08-11-winter-survival-gdd.md) — pillars, 7-day structure, survival model, three endings
   - [Art Bible](Docs/superpowers/specs/2026-08-11-winter-survival-art-bible.md) — 12-color palette, 12 hard modeling rules, lighting presets, asset pipeline
   - [System Map](Docs/superpowers/specs/2026-08-11-winter-survival-system-map.md) — folder layout, core abstractions, 31-task build order

[Docs/PROGRESS.md](Docs/PROGRESS.md) tracks completion and health across all seven waves. Reference material (video transcript, target screenshots, palette captures) lives in `Refs/game ref/` and is untracked.

### Running the tests

```bash
bash tools/run_tests.sh 98
```

Not the raw Godot command. The runner cannot see engine-level errors, so a test aborted *after* its first assertion still reports PASS — the wrapper is what catches that, by failing any run whose console is dirty. See AGENT-BRIEFING §1.

### Rules that bind all code

- **Filenames are English `snake_case`.** The source video's plan used Polish names (`zima`, `dolina`, `wrog`, …); these are deprecated — see System Map §0.
- **Data-driven:** adding a weather event, item, stat, or threat must require **zero `.gd` changes** — only a new `.tres` under `data/`.
- **Zero direct references between systems.** All cross-system communication goes through `EventBus`.
- **`src/core/` contains no game noun** — not even in comments. It must be copyable to an unrelated project unchanged.
- **No hardcoded colour in `src/`, `data/`, `scenes/`, `assets/`** — read from `data/palette/color_bible.tres`. Tests may hardcode expected values; asserting "`#8FB0D8` is in the palette" by reading it from the palette would be circular.
- **Every task ends with a test**, and the console must be pristine — a green summary with a stray `WARNING:` above it is a failure.

## Godot binary

The engine is installed outside the project and is not on `PATH`:

- `D:\Godot_v4.7.1\Godot_v4.7.1-stable_win64.exe` — GUI build (4.7.1 stable, matches the project's `4.7` feature tag)
- `D:\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe` — **use this one from the shell**; the non-console build detaches from the terminal, so `print()` output, script errors, and stack traces are lost

## Commands

Open the editor:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --path "D:/Godot resource/winter-time" --editor
```

Run the project (requires `run/main_scene` to be set in `project.godot` first):

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --path "D:/Godot resource/winter-time"
```

Run a single scene without setting a main scene:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --path "D:/Godot resource/winter-time" res://path/to/scene.tscn
```

Reimport assets and rebuild `.godot/` after adding files or wiping the cache — do this before any headless run, since a missing import cache causes load failures rather than a silent reimport:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --path "D:/Godot resource/winter-time" --headless --import
```

Check a script for parse/type errors without launching the game:

```bash
"D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe" --path "D:/Godot resource/winter-time" --headless --check-only --script res://path/to/script.gd
```

**Tests and linting:** no test framework (GUT, gdUnit4) and no linter (`gdtoolkit`/`gdlint`) are installed or configured. There is no test command to run — set one up before writing tests rather than assuming one exists.

## Project settings that constrain code

These are set in `project.godot` and should inform how new systems are written:

- **Renderer: Forward+.** Rules out the Compatibility-only feature set; Mobile/Compatibility fallbacks are not a target. Shaders and rendering features can assume the full desktop pipeline.
- **3D physics: Jolt Physics** (not Godot Physics). Jolt's behavior diverges from the default engine on contact reporting, soft bodies, and some joint types — check Jolt-specific docs when physics results look wrong, and note that a few Godot Physics properties are ignored under Jolt.
- **Rendering driver on Windows: Direct3D 12** rather than the Vulkan default. Driver-level rendering bugs may be D3D12-specific; testing against `--rendering-driver vulkan` is a useful way to isolate them.
- **Window stretch: `canvas_items` mode with `expand` aspect.** UI and 2D scale with resolution while extra screen area is revealed rather than letterboxed, so anchor UI to the appropriate screen edges instead of relying on a fixed viewport size.

## Repository conventions

- `.godot/` is generated cache and is gitignored — never edit it or commit it.
- `.gitattributes` enforces `eol=lf` for all text files. Godot writes `.tscn`/`.tres`/`.gd` as LF; keep it that way.
- Every imported asset has a companion `.import` file (see `icon.svg.import`). Both the asset and its `.import` file belong in version control.

## Related reference projects

The parent directory `D:\Godot resource\` holds unrelated third-party Godot sample projects (TPS strafing, IK aim, parkour, FPS series, RPG character, and others). They are **not** part of this project — do not modify them, and do not treat their code as this project's conventions. They are available as reference material if asked to draw on a specific technique.
