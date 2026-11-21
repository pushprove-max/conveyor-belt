#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what a graded SWE-bench result keeps beyond resolved (bench/swe_harness.py's grade, bench/swe.sh): its
# class from the hidden-test report, the reference fix's size, and the patch's measures; and how `bench swe show`,
# `history` and `results --json` read them (null, not kept, in a result older than them). The grade cases run the real
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
  run) rm -rf "$C/box" && cp -r "$C/base" "$C/box" ;;
  cp) case $2 in *:/testbed/*) cp "$C/box/${2#*:/testbed/}" "$3" ;; *) cp "$2" "$C/box.patch" ;; esac ;;
  exec) cd "$C/box" && exec bash -c "source() { :; }; conda() { :; }; ${7//\/tmp\/conveyor.patch/$C/box.patch}" ;;
  rm) rm -rf "$C/box" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$C/bin/docker"
  swebase lib/x.py 'keep\nold\n'
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
SWEPATCH=('diff --git a/lib/x.py b/lib/x.py' '--- a/lib/x.py' '+++ b/lib/x.py' '@@ -1,2 +1,2 @@' ' keep' '-old' '+new')

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
  jq -e '.measures | del(.lintClean, .provesFix) == {files: 2, codeAdded: 2, codeRemoved: 2, testAdded: 3, size: 2, strays: false}' <<<"$out" > /dev/null \
    || fail "the patch measures of twice the reference fix's code lines, in its file and a new test file, are not size 2.0, strays false: $out"
}
t_swegradestray() {
  local out; swegradefx "$T/$CASE"
  out=$(swegrade '["t1","t2","t3","t4"]' 'diff --git a/lib/y.py b/lib/y.py' '--- a/lib/y.py' '+++ b/lib/y.py' '@@ -1 +1 @@' '--- a line that starts with dashes' '+new') || fail "the grade failed: $out"
  [ "$(jq -c '.measures | [.strays, .codeAdded, .codeRemoved]' <<<"$out")" = '[true,1,1]' ] \
    || fail "a patch that changes a code file the reference fix does not change is not strays true (a removed line of dashes counts as a line): $out"
}

# Bug: a result did not say whether the patch left the code clean. A patch that adds an unused import is lintClean
# false; a patch that adds none is true, even when the file already had an unused import (the base's own problem).
t_swegradelintdirty() {
  local out; swegradefx "$T/$CASE"; swebase lib/x.py 'import os\n\n\ndef f():\n    return os.getcwd()\n'
  out=$(swegradefiles lib/x.py 'import os\nimport sys\n\n\ndef f():\n    return os.getcwd()\n') || fail "the grade failed: $out"
  [ "$(jq -c .measures.lintClean <<<"$out")" = false ] || fail "a patch that adds an unused import is not lintClean false: $out"
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
  swe; local out id=r20261117T090000-1
  mkdir -p "$B/results/stub-a" && jq -nc '{task: "proj__a-1", arm: "stub-a", key: "stub-a", label: "stub-a", resolved: true, fired: true, sessions: 1, tokens: 3, minutes: 1, steps: []}' > "$B/results/stub-a/proj__a-1.json" \
    && jq -nc --arg id "$id" '{id: $id, arms: ["stub-a"], cols: [{arm: "stub-a", key: "stub-a"}], n: 1, started: "2026-11-17T09:00:00Z", state: "done", tasks: [{id: "proj__a-1", arm: "stub-a", result: "resolved"}]}' > "$B/runs.jsonl" \
    || fail "the old result could not be written"
  out=$(loop bench swe show "$id") && [ "$(jq -c '.tasks[0].cells[0] | [.resolved, .class, .tests, .ref, .measures]' <<<"$out")" = '[true,null,null,null,null]' ] || fail "show does not give a result kept before as not kept: $out"
  out=$(loop bench swe results --json) && [ "$(jq -c '.[0] | [.classes, (.tasks[0] | [.class, .tests, .ref, .measures])]' <<<"$out")" = '[null,[null,null,null,null]]' ] || fail "results --json does not give a result kept before as not kept: $out"
  out=$(loop bench swe history) && [ "$(jq -c '.runs[0].cols[0].classes' <<<"$out")" = null ] || fail "history does not give the classes of a run's old results as not kept: $(jq -c '.runs[0].cols' <<<"$out")"
}
