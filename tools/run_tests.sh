#!/usr/bin/env bash
#
# run_tests.sh -- run the WinterTime suite and fail on anything the runner
#                 itself cannot see.
#
# Usage:
#   tools/run_tests.sh              # run the suite, require clean output
#   tools/run_tests.sh 89           # ...and require exactly 89 passing tests
#
# Exit status: 0 only when the suite passed AND the output was clean.
#              1 when anything was wrong. 2 on bad usage.
#
# On a clean run this script prints NOTHING of its own -- only Godot's output,
# echoed through live. The suite's output must stay pristine (briefing §2.1),
# and a wrapper that stamped "all good" on the end would itself be noise.
# Silence plus exit 0 is the success signal.
#
# ---------------------------------------------------------------------------
# WHY scan the output? Isn't the runner's exit code enough?
# ---------------------------------------------------------------------------
# No, and this project has now been bitten three times by exactly that
# assumption. The runner can only report on what it observes, and a GDScript
# test can break in ways the runner never observes at all:
#
#   1. A test *file* that fails to parse yields zero test methods, so it used
#      to be skipped in silence. test_discovery.gd + test_runner.gd now turn
#      that into a failure.
#
#   2. A test *method* aborted mid-flight by a GDScript runtime error records
#      no failures -- the VM drops the rest of the function and returns
#      quietly -- so it scored as a pass. test_case.gd's assertion counter now
#      turns a method that executed ZERO assertions into a failure.
#
#   3. But (2) has a demonstrated residual gap: an abort that happens *after*
#      the first assertion still reports PASS, because the counter is already
#      non-zero. The test ran one line, died, and looked green.
#
# The engine does print a `SCRIPT ERROR` line when that happens -- to the
# console, where nothing was looking. Same for leaked Nodes (`WARNING: N
# ObjectDB instances were leaked at exit`, briefing §2.2), leaked RIDs, and
# parse errors in files the runner never loads. None of these reach the
# runner's tally; all of them mean the run cannot be trusted.
#
# So this wrapper judges the run by a second, independent standard: the
# console must be clean. A green summary underneath a stray engine error is a
# failure (briefing §2.1), and this is the thing that enforces it.
#
# It also insists the summary line is actually present. A run that crashed
# before reporting would otherwise produce no failure count at all, and
# "no failures were reported" is not the same as "nothing failed".
#
# ---------------------------------------------------------------------------

set -u

# The console build, always: the plain win64 exe detaches from the terminal
# and every print(), error and stack trace is lost -- which would defeat the
# entire point of this script. Overridable for a different install location.
GODOT_BIN="${GODOT_BIN:-D:/Godot_v4.7.1/Godot_v4.7.1-stable_win64_console.exe}"

# Any of these appearing anywhere in the output fails the run. Matched as
# fixed strings, case-sensitively -- `ERROR:` with its colon so that a test
# *named* something like `test_..._not_error` is not a false positive.
FORBIDDEN_PATTERNS=(
	'SCRIPT ERROR'  # GDScript runtime error -- may have aborted a test mid-method
	'ERROR:'        # any engine-level error, including leaked RIDs
	'WARNING:'      # includes leaked ObjectDB instances (an un-freed Node)
	'Parse Error'   # a script that did not compile
	'leaked'        # belt and braces: the leak wording, whatever prefix it carries
	'still in use'  # resources alive at shutdown
)

# --- arguments -------------------------------------------------------------

if [ "$#" -gt 1 ]; then
	echo "run_tests.sh: usage: run_tests.sh [expected-pass-count]" >&2
	exit 2
fi

expected_passed="${1:-}"
if [ -n "$expected_passed" ] && ! printf '%s' "$expected_passed" | grep -Eq '^[0-9]+$'; then
	echo "run_tests.sh: expected-pass-count must be a non-negative integer, got '${expected_passed}'" >&2
	exit 2
fi

# --- locate the project ----------------------------------------------------

# Derived from this script's own location (tools/ sits at the project root) so
# the wrapper keeps working if the checkout moves. Godot on Windows needs a
# native path, not the /d/... form Git Bash reports.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
if command -v cygpath >/dev/null 2>&1; then
	project_dir="$(cygpath -w "${project_dir}")"
fi

# --- run -------------------------------------------------------------------

tmp_dir="$(mktemp -d)"
if [ -z "${tmp_dir}" ] || [ ! -d "${tmp_dir}" ]; then
	echo "run_tests.sh: could not create a temporary directory for the captured log" >&2
	exit 2
fi
trap 'rm -rf "${tmp_dir}"' EXIT
raw_log="${tmp_dir}/raw.log"
scan_log="${tmp_dir}/scan.log"

# stderr folded into stdout so engine errors -- which go to stderr -- are
# scanned too; tee so a human still watches it live.
"${GODOT_BIN}" --headless --path "${project_dir}" \
	--script res://tests/framework/test_runner.gd 2>&1 | tee "${raw_log}"
godot_status="${PIPESTATUS[0]}"

# Godot writes CRLF here. Strip the CR so end-of-line anchors match.
tr -d '\r' < "${raw_log}" > "${scan_log}.crlf"

# --- the third-party allowlist ---------------------------------------------
#
# THE GATE STAYS ABSOLUTE FOR ANYTHING WE COULD HAVE CAUSED. This list exists
# only for lines emitted by an installed third-party addon, which we have read,
# understood, and can name -- and which no change of ours can make appear or
# disappear.
#
# Adding a line here is a Director decision, not a way past a red run. The gate
# has already caught FIVE separate false-PASS mechanisms in this project; every
# entry below narrows it, so each one must earn its place and say why.
#
# Match is by fixed string on the whole line, deliberately: a pattern broad
# enough to be convenient is broad enough to swallow one of ours.
THIRD_PARTY_NOISE=(
	# beehave registers its debugger capture from its EditorPlugin, which does
	# not load under --headless. Its runtime then sends a message nothing is
	# listening for. Benign, unreachable from our code, and unavoidable while
	# the addon is enabled. Remove this line the day beehave is removed.
	'ERROR: Capture not registered: '"'"'beehave'"'"'.'
)

cp "${scan_log}.crlf" "${scan_log}"
suppressed=0
for noise in "${THIRD_PARTY_NOISE[@]}"; do
	hits="$(grep -cF -- "${noise}" "${scan_log}" || true)"
	if [ "${hits:-0}" -gt 0 ]; then
		suppressed=$((suppressed + hits))
		grep -vF -- "${noise}" "${scan_log}" > "${scan_log}.tmp" && mv "${scan_log}.tmp" "${scan_log}"
		# Announced, never silent: a suppression nobody sees is a place for our
		# own errors to hide, which is the exact failure this gate exists for.
		echo "run_tests.sh: allowed ${hits} third-party line(s): ${noise}" >&2
	fi
done
rm -f "${scan_log}.crlf"

# --- judge -----------------------------------------------------------------

problems=()

if [ "${godot_status}" -ne 0 ]; then
	problems+=("Godot exited with status ${godot_status} (the runner exits 1 when any test fails).")
fi

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
	if grep -qF -- "${pattern}" "${scan_log}"; then
		problems+=("output contains \"${pattern}\", which must never appear in a clean run:")
		while IFS= read -r line; do
			problems+=("      line ${line}")
		done < <(grep -nF -- "${pattern}" "${scan_log}" | head -5)
	fi
done

# The runner's own bottom line: "N passed, M failed".
summary="$(grep -E '^[0-9]+ passed, [0-9]+ failed$' "${scan_log}" | tail -1)"
if [ -z "${summary}" ]; then
	problems+=("no summary line ('N passed, M failed') in the output -- the run never reached its report, so nothing here can be trusted.")
else
	passed="${summary%% *}"
	failed_tail="${summary#*, }"
	failed="${failed_tail%% *}"

	if [ "${failed}" -ne 0 ]; then
		problems+=("the runner reported ${failed} failing test(s).")
	fi
	if [ -n "${expected_passed}" ] && [ "${passed}" -ne "${expected_passed}" ]; then
		problems+=("expected ${expected_passed} passing test(s), the runner reported ${passed}.")
	fi
fi

# --- verdict ---------------------------------------------------------------

if [ "${#problems[@]}" -eq 0 ]; then
	exit 0
fi

{
	echo ""
	echo "run_tests.sh: FAILED -- this run is not trustworthy:"
	for problem in "${problems[@]}"; do
		echo "  - ${problem}"
	done
	echo ""
} >&2
exit 1
