#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the swebench release the SWE-bench harness (bench/swe_harness.py) needs, as `conveyor.sh bench swe`
# reports it. The real swe_harness.py runs on a stand-in swebench package; the fixture of the arms check cases is
# swebench.test.sh's swe().
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A stand-in swebench <version> in folder <folder>, as swebench 5 is: no MAP_REPO_VERSION_TO_SPECS in its constants;
# a stand-in datasets beside it.
swebenchstub() { # <folder> <version>
  mkdir -p "$1/swebench/harness" "$1/datasets" && printf '__version__ = "%s"\n' "$2" > "$1/swebench/__init__.py" \
    && : > "$1/swebench/harness/__init__.py" && echo 'MAP_REPO_VERSION_TO_SPECS_BY_REPO = {}' > "$1/swebench/harness/constants.py" \
    && echo 'def load_dataset(*a, **k): return []' > "$1/datasets/__init__.py" || fail "the stand-in swebench was not made"
}

# Bug (#630): with swebench 5 (what `pip install swebench` gave) tasks failed with an ImportError, and the error said
# only that the swebench package is needed, which it was; nothing said which release to install.
t_sweharnessver() {
  local C=$T/$CASE out rc
  mkdir -p "$C/tmp" && swebenchstub "$C/m" 5.0.2
  # No .pyc: the stand-in's version is rewritten within the same second at the same size, which a cached .pyc hides.
  h() { env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$C/m" TMPDIR="$C/tmp" HOME="$C" python3 "$SRC/bench/swe_harness.py" "$@"; }
  out=$(h tasks o/ds rev1 "$C/list" 2>&1); rc=$?
  [ "$rc" != 0 ] || fail "tasks passed with a swebench that has no MAP_REPO_VERSION_TO_SPECS: $out"
  grep -q '^conveyor: the SWE-bench harness has swebench 5\.0\.2; it needs swebench==4\.1\.0' <<<"$out" \
    || fail "the error does not name the installed swebench and the one to install: $out"
  # The preflight's check: the wrong release fails with the same words, the right one passes and prints nothing.
  out=$(h check 2>&1) && fail "check passed with swebench 5.0.2: $out"
  grep -q 'has swebench 5\.0\.2; it needs swebench==4\.1\.0' <<<"$out" || fail "check does not name the installed swebench and the one to install: $out"
  swebenchstub "$C/m" 4.1.0
  out=$(h check 2>&1) && [ -z "$out" ] || fail "check failed with swebench 4.1.0: $out"
}

# Bug (#630): the Benchmarks tab's check of an arm showed "the harness needs Python with the swebench package" with
# swebench 5 installed; the preflight passed a harness whose swebench is not the release it is written for.
t_swearmswebench() {
  swe; local C=$T/$CASE out
  swebenchstub "$C/m" 5.0.2
  # The real harness, on the stand-in swebench, for every call: the task list cannot be read, and the error says why.
  printf '#!/usr/bin/env bash\nexec env PYTHONPATH=%q python3 "$@"\n' "$C/m" > "$C/real" && chmod +x "$C/real" || fail "the harness wrapper was not made"
  out=$(CONVEYOR_BENCH_PYTHON=$C/real loop bench swe arms check stub-a 2>&1) && fail "the check passed with swebench 5.0.2: $out"
  grep -q '^conveyor: the SWE-bench harness has swebench 5\.0\.2; it needs swebench==4\.1\.0' <<<"$out" \
    || fail "the check's error does not name the installed swebench and the one to install: $out"
  # The fixture's stub harness for the task list and images, the real one for check: the preflight fails and says why.
  printf '#!/usr/bin/env bash\n[ "$2" = check ] && exec %q "$@"\nexec %q "$@"\n' "$C/real" "$SWE_FX/py" > "$C/mixed" && chmod +x "$C/mixed" || fail "the harness wrapper was not made"
  out=$(CONVEYOR_BENCH_PYTHON=$C/mixed loop bench swe arms check stub-a 2>&1) && fail "the preflight passed with swebench 5.0.2: $out"
  grep -q '^stub-a: failed: the SWE-bench harness has swebench 5\.0\.2; it needs swebench==4\.1\.0' <<<"$out" \
    || fail "the preflight does not name the installed swebench and the one to install: $out"
}

# Bug (#630 review): with swebench 4.1.0, no saved task list and no access to Hugging Face, the check dropped the
# download's traceback and said the harness needs the swebench package, which it had.
t_swetasksdownload() {
  swe; local C=$T/$CASE out
  swebenchstub "$C/m" 4.1.0
  echo 'MAP_REPO_VERSION_TO_SPECS = {}' > "$C/m/swebench/harness/constants.py" \
    && printf 'def load_dataset(*a, **k):\n    raise ConnectionError("HUB-UNREACHABLE o/ds")\n' > "$C/m/datasets/__init__.py" \
    && printf '#!/usr/bin/env bash\nexec env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=%q python3 "$@"\n' "$C/m" > "$C/real" && chmod +x "$C/real" \
    || fail "the stand-in harness was not made"
  out=$(CONVEYOR_BENCH_PYTHON=$C/real loop bench swe arms check stub-a 2>&1) && fail "the check passed with no task list: $out"
  grep -q '^Traceback' <<<"$out" || fail "the download's traceback was dropped: $out"
  grep -q '^conveyor: the SWE-bench task list could not be read: ConnectionError: HUB-UNREACHABLE o/ds' <<<"$out" \
    || fail "the error does not name why the download failed: $out"
  ! grep -q 'needs Python with the swebench package' <<<"$out" || fail "the error blames a missing swebench package: $out"
}
