#!/usr/bin/env bash
#
# probe_take.sh -- measure a wanderer animation delivery before anyone believes
#                  its filename.
#
# Usage:
#   tools/probe_take.sh assets/source/characters/animations/fall_backward_hard.fbx
#   tools/probe_take.sh "Refs/game ref/.../Whatever_Meshy_Called_It.fbx"
#
# Prints tools/measure_wanderer_takes.gd's report for the file and exits 0 only
# if every take in it MOVES.
#
# ---------------------------------------------------------------------------
# WHY A SCRIPT AND NOT SIX COMMANDS
# ---------------------------------------------------------------------------
# The wanderer's animation deliveries live under assets/source/, which carries a
# .gdignore -- so Godot never imports them and ResourceLoader cannot open them.
# That is correct (see Docs/asset-inventory-meshy-wanderer.md section 3) and it
# means measuring one is a six-step dance: copy it somewhere Godot does look,
# reimport, run the measurer, read, delete the copy, reimport again. Every step
# is skippable and the one people skip is the last, which leaves a 16 MB FBX and
# a 12 MB extracted PNG in the project for the next agent to wonder about.
#
# It also removes the trap that the copy carries: Godot's FBX importer defaults
# `animation/trimming` to TRUE and its .glb importer defaults it to FALSE, so a
# take measured through a fresh FBX import and the same take measured after the
# Blender merge are not automatically being asked the same question. Briefing
# trap 15.2 is what that costs -- a take arriving at 8.958 s against a true
# 3.958 s, playing five seconds of nothing first. This pins it OFF, matching the
# character model, and says so.

set -u

GODOT_BIN="${GODOT_BIN:-D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe}"
PROBE_DIR="_probe_take"

if [ "$#" -ne 1 ]; then
	echo "probe_take.sh: usage: probe_take.sh <path-to-fbx-or-glb>" >&2
	exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
source_file="$1"
if [ ! -f "${source_file}" ]; then
	source_file="${project_dir}/$1"
fi
if [ ! -f "${source_file}" ]; then
	echo "probe_take.sh: no such file: $1" >&2
	exit 2
fi

godot_path="${project_dir}"
if command -v cygpath >/dev/null 2>&1; then
	godot_path="$(cygpath -w "${project_dir}")"
fi

base="$(basename "${source_file}")"
extension="${base##*.}"
name="$(basename "${base}" ".${extension}")"
probe="${project_dir}/${PROBE_DIR}"

# Always from scratch: a stale probe from an interrupted run would be measured
# instead of the file that was asked for, and it would look like a clean result.
rm -rf "${probe}"
mkdir -p "${probe}"
# The extracted-image sidecar and the .import land in here too, so removing the
# directory removes every trace.
trap 'rm -rf "${probe}"; "${GODOT_BIN}" --headless --path "${godot_path}" --import >/dev/null 2>&1' EXIT

cp "${source_file}" "${probe}/${name}.${extension}"

"${GODOT_BIN}" --headless --path "${godot_path}" --import >/dev/null 2>&1

# Match the character model rather than the format default. Written after the
# first import, because Godot generates the .import file and would overwrite an
# edit made before it existed.
import_file="${probe}/${name}.${extension}.import"
if [ -f "${import_file}" ]; then
	sed -i 's|^animation/trimming=true$|animation/trimming=false|' "${import_file}"
	"${GODOT_BIN}" --headless --path "${godot_path}" --import >/dev/null 2>&1
fi

"${GODOT_BIN}" --headless --path "${godot_path}" \
	--script res://tools/measure_wanderer_takes.gd \
	-- "res://${PROBE_DIR}/${name}.${extension}"
status="$?"

exit "${status}"
