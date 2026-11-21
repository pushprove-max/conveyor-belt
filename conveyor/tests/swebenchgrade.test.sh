#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what a graded SWE-bench result keeps beyond resolved (bench/swe_harness.py's grade, bench/swe.sh): its
# class from the hidden-test report, the reference fix's size, and the patch's measures; and how `bench swe show`,
# `history` and `results --json` read them (null, not kept, in a result older than them), with clean, the conveyor steps,
# the time limit and the per-arm figures of a key's results. The grade cases run the real
# swe_harness.py on stand-in datasets and swebench modules; the reader cases use swebench.test.sh's swe().
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The stand-in dataset has one task with the hidden tests t1 and t2 (fail to pass) and t3 and t4 (pass to pass), and a
# reference fix of one code file (lib/x.py: 1 line added, 1 removed) and one test file (tests/test_x.py: 2 added). The
# stand-in harness passes the tests that $SWE_PASSED (a JSON list of names) lists and writes the report of the instance
# as the official one does. The reference fix's text holds REFFIX and the hidden tests' HIDDENTEST.
# swegradefx <case folder>: sets C (its folder) and defines h, the real harness script on those stand-ins.
swegradefx() {
  C=$1; local M=$1-mods
  mkdir -p "$C/tmp" "$C/home" "$M/datasets" "$M/swebench/harness" || fail "the case's folders were not made"
  printf '%s\n' 'import json, os' 'def load_dataset(name, split, revision):' \
    '    fix = "diff --git a/lib/x.py b/lib/x.py\n--- a/lib/x.py\n+++ b/lib/x.py\n@@ -1,2 +1,2 @@\n keep\n-REFFIX-old\n+REFFIX-new\n'\
'diff --git a/tests/test_x.py b/tests/test_x.py\n--- a/tests/test_x.py\n+++ b/tests/test_x.py\n@@ -1 +1,3 @@\n keep\n+REFFIX-test\n+REFFIX-test\n"' \
    '    rows = [{"instance_id": "o__p-1", "repo": "o/p", "version": "1", "base_commit": "c1", "problem_statement": "issue", "patch": fix, "test_patch": "HIDDENTEST",' \
    '             "FAIL_TO_PASS": json.dumps(["t1", "t2"]), "PASS_TO_PASS": json.dumps(["t3", "t4"])}]' \
    '    d = os.path.join(os.environ["HF_HOME"], "datasets"); os.makedirs(d, exist_ok=True)' \
    '    open(os.path.join(d, revision + ".json"), "w").write(json.dumps(rows))' \
    '    return rows' > "$M/datasets/__init__.py"
  : > "$M/swebench/__init__.py"; : > "$M/swebench/harness/__init__.py"
  printf '%s\n' 'import json, os, sys' 'a = dict(zip(sys.argv[1::2], sys.argv[2::2]))' 'i = a["--instance_ids"]' \
    'row = json.loads(open(a["--dataset_name"]).readline()); ok = json.load(open(os.environ["SWE_PASSED"]))' \
    'def part(k): n = json.loads(row[k]); return {"success": [t for t in n if t in ok], "failure": [t for t in n if t not in ok]}' \
    'st = {"FAIL_TO_PASS": part("FAIL_TO_PASS"), "PASS_TO_PASS": part("PASS_TO_PASS")}' \
    'res = not st["FAIL_TO_PASS"]["failure"] and not st["PASS_TO_PASS"]["failure"]' \
    'open("conveyor.%s.json" % a["--run_id"], "w").write(json.dumps({"resolved_ids": [i] if res else []}))' \
    'd = "logs/run_evaluation/%s/conveyor/%s" % (a["--run_id"], i); os.makedirs(d)' \
    'open(d + "/report.json", "w").write(json.dumps({i: {"resolved": res, "tests_status": st}}))' > "$M/swebench/harness/run_evaluation.py"
  # The test command of the stand-in task is python3, which runs a test file as a script. ruff is the real one, as a module.
  echo 'MAP_REPO_VERSION_TO_SPECS = {"o/p": {"1": {"test_cmd": "python3"}}}' > "$M/swebench/harness/constants.py"
  mkdir -p "$M/ruff" "$C/bin" && printf '%s\n' 'import os, sys' 'os.execvp("ruff", ["ruff"] + sys.argv[1:])' > "$M/ruff/__main__.py"
  # The task's container is a copy of the repository $C/base (a git repository, the base commit), in $C/box: /testbed is
  # $C/box, the patch copied into the container is $C/box.patch, and a command runs on this machine in $C/box, with the
  # conda commands that start the task's environment doing nothing.
  # stub: no real Docker or task image in a test; it answers the few commands the harness gives (run, cp, exec, rm).
  cat > "$C/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$C/docker.log"
case $1 in
  run) [ ! -e "$C/nodocker" ] || exit 1; rm -rf "$C/box" && cp -r "$C/base" "$C/box" ;;
  cp) case $2 in *:/testbed/*) cp "$C/box/${2#*:/testbed/}" "$3" ;; *) cp "$2" "$C/box.patch" ;; esac ;;
  exec) cd "$C/box" && exec bash -c "source() { :; }; conda() { :; }; ${7//\/tmp\/conveyor.patch/$C/box.patch}" ;;
  rm) rm -rf "$C/box" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$C/bin/docker"
  swebase lib/x.py 'keep\n# old\n'
  h() { env C="$C" PATH="$C/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$C-mods" TMPDIR="$C/tmp" HOME="$C/home" HF_HOME="$C/home/hf" python3 "$SRC/bench/swe_harness.py" "$@"; }
}
# swebase <path> <content>...: the base commit's files, in the repository $C/base (content as printf %b reads it).
swebase() {
  mkdir -p "$C/base" && git -C "$C/base" init -q || fail "the base repository was not made"
  while [ $# -gt 1 ]; do mkdir -p "$C/base/$(dirname "$1")" && printf '%b' "$2" > "$C/base/$1" || fail "the base file $1 was not written"; shift 2; done
  git -C "$C/base" add -A && git -C "$C/base" -c user.name=t -c user.email=t@example.com commit -q -m base || fail "the base commit was not made"
}
# swegradefiles <path> <content>...: grades the change of those files of the base repository (git's own diff, a new
# file too) with every hidden test passing, and prints the harness's result.
swegradefiles() {
  rm -rf "$C/work" && cp -r "$C/base" "$C/work" || fail "the work copy was not made"
  while [ $# -gt 1 ]; do mkdir -p "$C/work/$(dirname "$1")" && printf '%b' "$2" > "$C/work/$1" || fail "the file $1 was not written"; shift 2; done
  git -C "$C/work" add -A -N && git -C "$C/work" diff --src-prefix=a/ --dst-prefix=b/ > "$C/patch" || fail "the patch was not made"
  echo '["t1","t2","t3","t4"]' > "$C/passed.json"
  SWE_PASSED=$C/passed.json h grade o/ds rev1 o__p-1 "$C/patch" "$C/grade" r1
}
# swegrade <passed tests, as a JSON list> <patch lines>...: grades a patch of those lines (git diff text) on the stand-in
# and prints the harness's result; the patch's text and the grade's folder are in $C.
swegrade() {
  local p=$1; shift
  printf '%s\n' "$p" > "$C/passed.json"; printf '%s\n' "$@" > "$C/patch"
  SWE_PASSED=$C/passed.json h grade o/ds rev1 o__p-1 "$C/patch" "$C/grade" r1
}
# A patch that fixes the code file as the reference fix does (2 code lines), the base of the cases below.
SWEPATCH=('diff --git a/lib/x.py b/lib/x.py' '--- a/lib/x.py' '+++ b/lib/x.py' '@@ -1,2 +1,2 @@' ' keep' '-# old' '+# new')

# Bug: a result kept only resolved yes or no, so a patch that fixed the task and broke another test looked the same as
# one that fixed nothing. A patch that makes every fail-to-pass test pass and fails one pass-to-pass test is `broke`,
# with the counts and the failed test's name; the reference fix's size is kept, and no text of the reference fix or of
# a hidden test stays in the result or the grade's folder.
t_swegradebroke() {
  local out; swegradefx "$T/$CASE"
  out=$(swegrade '["t1","t2","t3"]' "${SWEPATCH[@]}") || fail "the grade failed: $out"
  [ "$(jq -c '[.resolved, .class, .tests]' <<<"$out")" = '[false,"broke",{"failToPass":{"passed":2,"failed":0,"failedTests":[]},"passToPass":{"passed":1,"failed":1,"failedTests":["t4"]}}]' ] \
    || fail "a patch that fixes the task and breaks one other test is not class broke with its counts and the failed test: $out"
  [ "$(jq -c .ref <<<"$out")" = '{"code":{"files":1,"added":1,"removed":1},"test":{"files":1,"added":2,"removed":0}}' ] \
    || fail "the reference fix's size (code and test files) is not kept: $out"
  # Bug: an unresolved patch was counted clean when its other measures held. The patch is a comment swap, so lint, size
  # and strays all hold, and resolved is the only measure that can make clean false.
  [ "$(jq -c '.measures | [.lintClean, .strays, .size <= 2, .clean]' <<<"$out")" = '[true,false,true,false]' ] \
    || fail "an unresolved patch whose lint, size and strays hold is not clean false: $out"
  ! grep -rlE 'REFFIX|HIDDENTEST' "$C" && ! grep -qE 'REFFIX|HIDDENTEST' <<<"$out" || fail "text of the reference fix or a hidden test is in the result or on disk after the grade: $out"
}
t_swegradepartial() {
  local out; swegradefx "$T/$CASE"
  out=$(swegrade '["t1","t3","t4"]' "${SWEPATCH[@]}") || fail "the grade failed: $out"
  [ "$(jq -c '[.class, .tests.failToPass.passed, .tests.failToPass.failed]' <<<"$out")" = '["partial",1,1]' ] \
    || fail "a patch that makes some fail-to-pass tests pass is not class partial: $out"
}
t_swegradenofix() {
  local out; swegradefx "$T/$CASE"
  out=$(swegrade '["t3","t4"]' "${SWEPATCH[@]}") || fail "the grade failed: $out"
  [ "$(jq -c '[.class, .tests.failToPass.passed, .tests.failToPass.failedTests]' <<<"$out")" = '["nofix",0,["t1","t2"]]' ] \
    || fail "a patch that makes no fail-to-pass test pass is not class nofix: $out"
}
t_swegraderesolved() {
  local out; swegradefx "$T/$CASE"
  out=$(swegrade '["t1","t2","t3","t4"]' "${SWEPATCH[@]}") || fail "the grade failed: $out"
  [ "$(jq -c '[.resolved, .class, .tests.passToPass.failed]' <<<"$out")" = '[true,"resolved",0]' ] || fail "a patch that passes every hidden test is not class resolved: $out"
}

# Bugs: a patch that changed a file the reference fix leaves alone (a stray) showed no sign of it, and its size against
# the reference fix was not kept. A patch of 4 code lines against the reference fix's 2 is size 2.0; one in another
# code file is strays true; a test file of the patch is not a stray and its added lines are test lines.
t_swegradesize() {
  local out; swegradefx "$T/$CASE"
  out=$(swegrade '["t1","t2","t3","t4"]' 'diff --git a/lib/x.py b/lib/x.py' '--- a/lib/x.py' '+++ b/lib/x.py' '@@ -1,4 +1,4 @@' ' keep' '-a' '-b' '+c' '+d' ' keep' \
    'diff --git a/tests/test_new.py b/tests/test_new.py' '--- /dev/null' '+++ b/tests/test_new.py' '@@ -0,0 +1,3 @@' '+one' '+two' '+three') || fail "the grade failed: $out"
  jq -e '.measures | del(.lintClean, .provesFix, .clean) == {files: 2, codeAdded: 2, codeRemoved: 2, testAdded: 3, size: 2, strays: false}' <<<"$out" > /dev/null \
    || fail "the patch measures of twice the reference fix's code lines, in its file and a new test file, are not size 2.0, strays false: $out"
}
t_swegradestray() {
  local out; swegradefx "$T/$CASE"
  out=$(swegrade '["t1","t2","t3","t4"]' 'diff --git a/lib/y.py b/lib/y.py' '--- a/lib/y.py' '+++ b/lib/y.py' '@@ -1 +1 @@' '--- a line that starts with dashes' '+new') || fail "the grade failed: $out"
  [ "$(jq -c '.measures | [.strays, .codeAdded, .codeRemoved]' <<<"$out")" = '[true,1,1]' ] \
    || fail "a patch that changes a code file the reference fix does not change is not strays true (a removed line of dashes counts as a line): $out"
  # Bug: a resolved patch with a stray file was counted clean.
  [ "$(jq -c .measures.clean <<<"$out")" = false ] || fail "a resolved patch with strays true is not clean false: $out"
}

# Bug: a result did not say whether the patch left the code clean. A patch that adds an unused import is lintClean
# false; a patch that adds none is true, even when the file already had an unused import (the base's own problem).
t_swegradelintdirty() {
  local out; swegradefx "$T/$CASE"; swebase lib/x.py 'import os\n\n\ndef f():\n    return os.getcwd()\n'
  out=$(swegradefiles lib/x.py 'import os\nimport sys\n\n\ndef f():\n    return os.getcwd()\n') || fail "the grade failed: $out"
  [ "$(jq -c .measures.lintClean <<<"$out")" = false ] || fail "a patch that adds an unused import is not lintClean false: $out"
  # Bug: a resolved patch with a lint finding was counted clean.
  [ "$(jq -c .measures.clean <<<"$out")" = false ] || fail "a resolved patch that is not lint clean is not clean false: $out"
}
# Bug: ruff ran as `python -m ruff` in the patched folder, so a patch that adds ruff.py ran its own code as ruff (here it
# prints no findings): the unused import the patch also adds went unseen, and lintClean was true.
t_swegradelintshadow() {
  local out; swegradefx "$T/$CASE"; swebase lib/x.py 'import os\n\n\ndef f():\n    return os.getcwd()\n'
  out=$(swegradefiles lib/x.py 'import os\nimport sys\n\n\ndef f():\n    return os.getcwd()\n' ruff.py 'print("[]")\n') || fail "the grade failed: $out"
  [ "$(jq -c .measures.lintClean <<<"$out")" = false ] || fail "a patch that adds an unused import and a ruff.py is not lintClean false (the ruff.py ran as ruff): $out"
}
t_swegradelintclean() {
  local out; swegradefx "$T/$CASE"; swebase lib/x.py 'import os\nimport json\n\n\ndef f():\n    return os.getcwd()\n'
  out=$(swegradefiles lib/x.py 'import os\nimport json\n\n\ndef f():\n    return os.getcwd() + "/"\n') || fail "the grade failed: $out"
  [ "$(jq -c .measures.lintClean <<<"$out")" = true ] || fail "a patch that adds no problem, in a file that had an unused import, is not lintClean true: $out"
  # Clean is resolved, lint clean, size 1 here (at most 2) and no strays: all four hold.
  [ "$(jq -c .measures.clean <<<"$out")" = true ] || fail "a resolved, lint clean patch of the reference fix's size in its own file is not clean true: $out"
}

# Bug: clean ignored the size limit: a resolved, lint clean patch with no strays that changes 8 code lines against the
# reference fix's 2 (size 4, over 2) was counted clean.
t_swegradecleansize() {
  local out; swegradefx "$T/$CASE"; swebase lib/x.py 'x = 1\ny = 2\n'
  out=$(swegradefiles lib/x.py 'a = 1\nb = 2\nc = 3\nd = 4\ne = 5\nf = 6\n') || fail "the grade failed: $out"
  [ "$(jq -c '.measures | [.lintClean, .strays, .size == 4, .clean]' <<<"$out")" = '[true,false,true,false]' ] || fail "a resolved, lint clean patch of size 4 with no strays is not clean false: $out"
}
# Bug: a measure that could not be taken was counted as false. With Docker not answering, lintClean is not known: a
# resolved patch of the reference fix's size with no strays is clean null (not known), never false.
t_swegradecleanunknown() {
  local out; swegradefx "$T/$CASE"; : > "$C/nodocker"; swebase lib/x.py 'x = 1\ny = 2\n'
  out=$(swegradefiles lib/x.py 'x = 1\ny = 3\n') || fail "the grade failed: $out"
  [ "$(jq -c '.measures | [.lintClean, .strays, .size == 1, .clean]' <<<"$out")" = '[null,false,true,null]' ] || fail "a resolved patch whose lintClean could not be measured is not clean null: $out"
}

# Bug: a result did not say whether the patch's new test shows the fix. A new test that fails on the base commit (with
# only the patch's test files) and passes with the patch is provesFix true; a new test that also passes on the base
# commit proves nothing, so false.
SWETESTPY='import sys\nsys.path.insert(0, "lib")\nimport x\nassert x.f() %s\n'
t_swegradeprovesfix() {
  local out; swegradefx "$T/$CASE"; swebase lib/x.py 'def f():\n    return 1\n'
  out=$(swegradefiles lib/x.py 'def f():\n    return 2\n' tests/test_f.py "$(printf "$SWETESTPY" '== 2')\n") || fail "the grade failed: $out"
  [ "$(jq -c .measures.provesFix <<<"$out")" = true ] || fail "a new test that fails on the base commit and passes with the patch is not provesFix true: $out $(cat "$C/docker.log")"
}
t_swegradeprovesnot() {
  local out; swegradefx "$T/$CASE"; swebase lib/x.py 'def f():\n    return 1\n'
  out=$(swegradefiles lib/x.py 'def f():\n    return 2\n' tests/test_f.py "$(printf "$SWETESTPY" 'in (1, 2)')\n") || fail "the grade failed: $out"
  [ "$(jq -c .measures.provesFix <<<"$out")" = false ] || fail "a new test that also passes on the base commit is not provesFix false: $out"
}

# What a new result shows in the three readers: the grade's class, tests, ref and measures in the result, in each task's
# cell of `show`, in each task of `results --json` and as the count of each class in `history`'s columns. The grade is the
# stand-in's, printing $SWE_FX/gradeout; the reader cases are of swe_trial's merge of the grade into the result.
t_swegradeshow() {
  swe; local out id g='{"resolved":false,"class":"broke","tests":{"failToPass":{"passed":2,"failed":0,"failedTests":[]},"passToPass":{"passed":1,"failed":1,"failedTests":["t4"]}},"ref":{"code":{"files":1,"added":1,"removed":1},"test":{"files":0,"added":0,"removed":0}},"measures":{"files":1,"codeAdded":2,"codeRemoved":2,"testAdded":0,"size":2.0,"strays":false}}'
  echo "$g" > "$SWE_FX/gradeout"
  out=$(loop bench swe 1 --arm stub-a 2>&1) || fail "the run failed: $out"
  id=$(loop bench swe history | jq -r '.runs[0].id')
  [ "$(jq -c 'del(.resolved) | [.class, .tests, .ref, .measures] == (input | [.class, .tests, .ref, .measures])' "$B"/results/stub-a-*/*.json <(echo "$g"))" = true ] \
    || fail "the result does not keep the grade's class, tests, ref and measures: $(cat "$B"/results/stub-a-*/*.json)"
  [ "$(loop bench swe show "$id" | jq -c '.tasks[0].cells[0] | [.class, .tests.passToPass.failedTests, .ref.code.added, .measures.size == 2]')" = '["broke",["t4"],1,true]' ] \
    || fail "show does not give the result's grade fields: $(loop bench swe show "$id" | jq -c '.tasks[0].cells[0]')"
  # The grade above has measures from before lintClean and provesFix: they show as null, not kept (never false).
  [ "$(loop bench swe show "$id" | jq -c '.tasks[0].cells[0].measures | [.lintClean, .provesFix]')" = '[null,null]' ] \
    || fail "show does not give lintClean and provesFix of a result kept before them as null: $(loop bench swe show "$id" | jq -c '.tasks[0].cells[0].measures')"
  [ "$(loop bench swe results --json | jq -c '.[0] | [.classes, (.tasks | map([.class, .measures.strays]))]')" = '[{"broke":1},[["broke",false]]]' ] \
    || fail "results --json does not give the class counts and each task's grade fields: $(loop bench swe results --json)"
  [ "$(loop bench swe history | jq -c '.runs[0].cols[0].classes')" = '{"broke":1}' ] || fail "history does not give the class counts of the run's arm: $(loop bench swe history | jq -c '.runs[0].cols')"
}

# Bug: a result kept before these fields were kept would show them as zero or as a class of its own. Every reader shows
# them as null: not kept.
t_swegradeold() {
  swe; local out f id=r20261117T090000-1
  mkdir -p "$B/results/stub-a" && jq -nc '{task: "proj__a-1", arm: "stub-a", key: "stub-a", label: "stub-a", resolved: true, fired: true, sessions: 1, tokens: 3, minutes: 1, steps: []}' > "$B/results/stub-a/proj__a-1.json" \
    && jq -nc --arg id "$id" '{id: $id, arms: ["stub-a"], cols: [{arm: "stub-a", key: "stub-a"}], n: 1, started: "2026-11-17T09:00:00Z", state: "done", tasks: [{id: "proj__a-1", arm: "stub-a", result: "resolved"}]}' > "$B/runs.jsonl" \
    || fail "the old result could not be written"
  # Each reader is called once: the grade's fields, then the later ones (timedOut, the conveyor steps, each per-arm figure), never zero or false.
  out=$(loop bench swe show "$id") && [ "$(jq -c '.tasks[0].cells[0] | [.resolved, .class, .tests, .ref, .measures, .timedOut, .findingsFixed, .fixRounds]' <<<"$out")" = '[true,null,null,null,null,null,null,null]' ] \
    || fail "show does not give the fields of a result kept before them as not kept: $out"
  f='[.classes, .failToPassPassed, .passToPassBroken, .clean, ([.medians[]] | all(. == null)), ([.rates[]] | all(. == null)), .sameTwice]'
  out=$(loop bench swe results --json) && [ "$(jq -c '.[0] | [.classes, (.tasks[0] | [.class, .tests, .ref, .measures, .timedOut, .findingsFixed, .fixRounds]), (.figures | '"$f"')]' <<<"$out")" \
    = '[null,[null,null,null,null,null,null,null],[null,null,null,null,true,true,null]]' ] || fail "results --json does not give a result kept before as not kept: $out"
  out=$(loop bench swe history) && [ "$(jq -c '[.runs[0].cols[0].classes, (.keys[] | select(.key == "stub-a") | .figures | '"$f"')]' <<<"$out")" = '[null,[null,null,null,null,true,true,null]]' ] \
    || fail "history does not give the classes and figures of a result kept before as not kept: $(jq -c '[.runs[0].cols, .keys]' <<<"$out")"
}

# Bug: a key's results were not added up: a reader had to count the classes, tests, measures and tokens itself, and a
# result with a measure not kept would have counted as zero. The per-arm figures of 5 results (4 resolved, one broke):
# class counts, the totals of fail-to-pass passed and pass-to-pass broken, the clean count, the medians and the rates of
# the measures over the resolved ones, and the tokens over the resolved count. Each rate is different, so one read from
# another's measure fails.
swefigres() { # <task> <resolved> <class> <tokens> <fail-to-pass passed> <pass-to-pass failed> <measures>
  mkdir -p "$B/results/figs" && jq -nc --arg t "$1" --argjson r "$2" --arg c "$3" --argjson k "$4" --argjson f "$5" --argjson p "$6" \
    '{task: $t, arm: "stub-a", key: "figs", resolved: $r, fired: true, sessions: 1, tokens: $k, minutes: 1, class: $c,
      tests: {failToPass: {passed: $f, failed: 0, failedTests: []}, passToPass: {passed: 3, failed: $p, failedTests: []}}, measures: '"$7"'}' > "$B/results/figs/$1.json"
}
t_swefigures() {
  swe; local out
  swefigres t1 true resolved 10 2 0 '{files: 2, codeAdded: 3, codeRemoved: 1, testAdded: 4, size: 1.5, strays: false, lintClean: true, provesFix: false, clean: true}'
  swefigres t2 true resolved 20 1 0 '{files: 1, codeAdded: 5, codeRemoved: 1, testAdded: 0, size: 3, strays: true, lintClean: true, provesFix: false, clean: false}'
  swefigres t3 true resolved 30 2 0 '{files: 3, codeAdded: 1, codeRemoved: 2, testAdded: 2, size: 1, strays: false, lintClean: true, provesFix: true, clean: true}'
  swefigres t4 false broke 40 2 1 '{files: 1, codeAdded: 1, codeRemoved: 1, testAdded: 0, size: 1, strays: false, lintClean: true, provesFix: false, clean: false}'
  swefigres t5 true resolved 50 2 0 '{files: 4, codeAdded: 7, codeRemoved: 4, testAdded: 6, size: 2, strays: true, lintClean: true, provesFix: false, clean: false}'
  out=$(loop bench swe results --json) || fail "results --json failed: $out"
  [ "$(jq -c '.[0].figures' <<<"$out")" = '{"classes":{"broke":1,"resolved":4},"failToPassPassed":9,"passToPassBroken":1,"clean":2,"medians":{"files":2.5,"codeAdded":4,"codeRemoved":1.5,"testAdded":3,"size":1.75},"rates":{"lintClean":1,"size":0.75,"strays":0.5,"provesFix":0.25},"tokensPerResolved":38,"sameTwice":null}' ] \
    || fail "results --json does not add up the key's results: $(jq -c '.[0].figures' <<<"$out")"
  out=$(loop bench swe history) || fail "history failed: $out"
  [ "$(jq -c '.keys[] | select(.key == "figs") | .figures.clean' <<<"$out")" = 2 ] || fail "history does not give the key's figures: $(jq -c .keys <<<"$out")"
}

# Bugs: an arm that ran a task twice on the same inputs and got a different result each time showed no sign of it, and
# no command ran a task twice on the same inputs (a kept result was always reused). Run 1 resolves the first task; run
# 2, with --again, runs it again and it is not resolved this time, and runs the second task once: same twice is 0 of 1
# task, below 1. Run 3 reuses both results: a reused task line is no run of it, else the second task, resolved on two
# lines, would make the figure 0.5.
t_sweseame() {
  swe; local out first
  first=$(sweorder | head -n 1)
  out=$(loop bench swe 1 --arm stub-a 2>&1) || fail "the first run failed: $out"
  echo "$first" > "$SWE_FX/wrong"
  out=$(loop bench swe 2 --arm stub-a --again 2>&1) || fail "the run with --again failed: $out"
  grep -q "1/2 $first: unresolved$" <<<"$out" || fail "bench swe 2 --again did not run $first again: $out"
  out=$(loop bench swe 2 --arm stub-a 2>&1) || fail "the third run failed: $out"
  [ "$(grep -c "(reused)$" <<<"$out")" = 2 ] || fail "bench swe 2 with no --again did not reuse both kept results: $out"
  out=$(loop bench swe results --json) || fail "results --json failed: $out"
  [ "$(jq -c '.[0].figures.sameTwice' <<<"$out")" = 0 ] \
    || fail "an arm that got its one task run twice a different result each time is not same twice 0: $(jq -c '.[0].figures' <<<"$out") $(cat "$B/runs.jsonl")"
  out=$(loop bench swe history) || fail "history failed: $out"
  [ "$(jq -c '.keys[0].figures.sameTwice' <<<"$out")" = 0 ] || fail "history does not give same twice 0: $(jq -c .keys <<<"$out")"
  # Bug: the --again run wrote its result and patch over the first run's, so the first run then showed the --again
  # run's outcome. Each run shows its own, and the kept result (results, figures) stays the first run's.
  local r1 r2; r1=$(jq -r '.runs[2].id' <<<"$out"); r2=$(jq -r '.runs[1].id' <<<"$out")
  # Bug (#1177): a run's line did not say it ran with --again, so the Board's Live run counted its tasks with a kept
  # result as reused (no time left, no cost) though the run runs each of them again.
  [ "$(jq -c '[.runs[] | .again]' <<<"$out")" = '[null,true,null]' ] || fail "history does not mark the --again run, and only it: $(jq -c '[.runs[] | [.id, .again]]' <<<"$out")"
  [ "$(loop bench swe show "$r1" | jq -c --arg t "$first" '[.tasks[] | select(.id == $t) | .cells[0] | .resolved, (.patch | length > 0)]')" = '[true,true]' ] \
    || fail "bench swe show $r1 (the first run) does not show its own resolved result and patch of $first: $(loop bench swe show "$r1" | jq -c '.tasks')"
  [ "$(loop bench swe show "$r2" | jq -c --arg t "$first" '[.tasks[] | select(.id == $t) | .cells[0].resolved]')" = '[false]' ] \
    || fail "bench swe show $r2 (the --again run) does not show its own unresolved result of $first: $(loop bench swe show "$r2" | jq -c '.tasks')"
  # Bug (#1177): show did not say which cell is a result kept apart, so the Board took diff's reading of the kept one
  # (results/<key>) as the reading of the --again run's own. The first run's cell is the kept one.
  [ "$(loop bench swe show "$r2" | jq -c --arg t "$first" '[.tasks[] | select(.id == $t) | .cells[0].again]')" = "[\"$r2\"]" ] \
    && [ "$(loop bench swe show "$r1" | jq -c --arg t "$first" '[.tasks[] | select(.id == $t) | .cells[0].again]')" = '[null]' ] \
    || fail "bench swe show does not mark the --again run's own result of $first apart from the kept one: $(loop bench swe show "$r2" | jq -c '.tasks')"
  [ "$(jq -c .resolved "$B"/results/*/"$first.json")" = true ] || fail "the --again run replaced the kept result of $first: $(cat "$B"/results/*/"$first.json")"
  # Deleting the --again run takes its own results and leaves the first run's.
  out=$(loop bench swe runs delete "$r2" 2>&1) || fail "bench swe runs delete $r2 failed: $out"
  [ ! -e "$B/again/$r2" ] && [ -s "$(echo "$B"/results/*/"$first.json")" ] \
    || fail "bench swe runs delete $r2 left its own results or took the first run's: $(ls -R "$B/again" "$B/results" 2>&1)"
}

# Bug (#1182): deleting the first run took the kept results of a key while two --again runs still showed it, so same
# twice vanished from results and history, or (when read from again/) the key was listed though a new run could not reuse
# it and diff could not read it. Run 1 resolves the first task, runs 2 and 3 (--again) both leave it unresolved; run 1 is
# deleted: the key stays under results/, same twice is 1, and a run with no --again reuses the kept result.
t_sweseamegone() {
  swe; local out res first r1 key
  first=$(sweorder | head -n 1)
  out=$(loop bench swe 1 --arm stub-a 2>&1) || fail "the first run failed: $out"
  echo "$first" > "$SWE_FX/wrong"
  out=$(loop bench swe 1 --arm stub-a --again 2>&1) || fail "the first --again run failed: $out"
  out=$(loop bench swe 1 --arm stub-a --again 2>&1) || fail "the second --again run failed: $out"
  r1=$(loop bench swe history | jq -r '.runs[2].id')
  out=$(loop bench swe runs delete "$r1" 2>&1) || fail "bench swe runs delete $r1 failed: $out"
  res=$(loop bench swe results --json) || fail "results --json failed: $res"
  [ "$(jq -c '[length, .[0].n, .[0].figures.sameTwice]' <<<"$res")" = '[1,1,1]' ] \
    || fail "results --json after deleting the first run does not give one key with 1 task and same twice 1: $(jq -c . <<<"$res")"
  out=$(loop bench swe history) || fail "history failed: $out"
  [ "$(jq -c '[.keys | length, .[0].figures.sameTwice]' <<<"$out")" = '[1,1]' ] \
    || fail "history after deleting the first run does not give one key with same twice 1: $(jq -c .keys <<<"$out")"
  key=$(jq -r '.[0].key' <<<"$res")
  out=$(loop bench swe diff "$key" "$key" 2>&1) || fail "bench swe diff $key $key after deleting the first run failed: $out"
  out=$(loop bench swe 1 --arm stub-a 2>&1) || fail "the run after deleting the first run failed: $out"
  grep -q "(reused)$" <<<"$out" || fail "a run after deleting the first run did not reuse the kept result: $out"
}

# Bug: same twice was rounded to two places, so an arm whose result changed on 1 of 201 tasks run twice showed 1, as
# if every task agreed. Two run lines of key figs run 201 tasks; the last one is resolved only the first time.
t_swesamenear() {
  swe; local out
  swefigres t1 true resolved 10 2 0 '{files: 1, codeAdded: 1, codeRemoved: 1, testAdded: 0, size: 1, strays: false, lintClean: true, provesFix: false, clean: true}'
  jq -nc 'range(2) as $i | {id: "r2026111\($i)T090000-1", arms: ["stub-a"], cols: [{arm: "stub-a", key: "figs"}], state: "done", started: "2026-11-1\($i)T09:00:00Z",
    tasks: [range(201) as $n | {id: "t\($n)", arm: "stub-a", reused: false, result: (if $i == 1 and $n == 200 then "unresolved" else "resolved" end)}]}' > "$B/runs.jsonl"
  out=$(loop bench swe results --json) || fail "results --json failed: $out"
  [ "$(jq -c '.[0].figures.sameTwice | . < 1 and . == 200 / 201' <<<"$out")" = true ] \
    || fail "an arm that changed its result on 1 of 201 tasks run twice is not same twice 200/201: $(jq -c '.[0].figures' <<<"$out")"
}

# Bug: a Conveyor arm's result kept its steps but not how many review findings its fix rounds went on, or whether the
# card's command reached the task's time limit. A card that blocked after two NO-GO reviews with one fix between them:
# 1 fix round and the 3 findings of the review the fix followed (the second review's 2 are not fixed). A card that
# landed at once: 0 and 0, not timed out. A command that ran to the limit is timedOut true.
t_swefixed() {
  swe; local out id
  out=$(loop bench swe 2 2>&1) || fail "the run failed: $out"
  [ "$(jq -c '[.fixRounds, .findingsFixed, .timedOut]' "$B"/results/*-"$EB"/proj__a-1.json)" = '[1,3,false]' ] \
    || fail "the card with a fix round does not keep fixRounds 1 and findingsFixed 3: $(jq -c '[.fixRounds, .findingsFixed, .timedOut, .steps[].step]' "$B"/results/*-"$EB"/proj__a-1.json)"
  [ "$(jq -c '[.fixRounds, .findingsFixed]' "$B"/results/*-"$EB"/proj__b-2.json)" = '[0,0]' ] || fail "the card with no fix round does not keep 0 and 0: $(cat "$B"/results/*-"$EB"/proj__b-2.json)"
  id=$(loop bench swe history | jq -r '.runs[0].id')
  [ "$(loop bench swe show "$id" | jq -c '[.tasks[].cells[0] | [.fixRounds, .findingsFixed, .timedOut]] | sort')" = '[[0,0,false],[1,3,false]]' ] \
    || fail "show does not give each task's fixRounds, findingsFixed and timedOut: $(loop bench swe show "$id" | jq -c '[.tasks[].cells[0]]')"
}
t_swetimedout() {
  swe; local out
  # The run's command is `timeout <limit> docker exec ... SWE_SB=<sandbox>/work/<task> SWE_PROMPT=...`: this stand-in for
  # timeout ends that call as timeout ends a command at its limit (exit 124), at once instead of after the minute that is
  # the shortest limit; any other call runs the real one.
  cat > "$SWE_FX/bin/timeout" <<'EOF'
#!/usr/bin/env bash
case "$*" in *SWE_SB=*/work/*SWE_PROMPT=*) exit 124 ;; esac
exec "$(PATH=${PATH//"$SWE_FX/bin:"/} command -v timeout)" "$@"
EOF
  chmod +x "$SWE_FX/bin/timeout"
  out=$(loop bench swe 1 --solo 2>&1) || fail "the solo run failed: $out"
  [ "$(jq -c .timedOut "$B"/results/solo-*/*.json)" = true ] || fail "a command that reached the time limit is not timedOut true: $(cat "$B"/results/solo-*/*.json) $out"
}
