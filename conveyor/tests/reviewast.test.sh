#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a Claude review with ast-grep installed runs cb-ast, the read-only ast-grep, and no command that writes.
# The helpers (modelsengine, rvcall) are models.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: with ast-grep installed, a Claude review cannot run cb-ast (no Bash tool, no allow rule, or the plugin's bin/
# not on its PATH), so its Class search is text search only; or its shell runs a command that writes: rm, touch,
# bash -c, cb-ast with a write option, cb-ast chained to another command (&&, ;, ||, &, a pipe), cb-ast with its output
# redirected, with a command substitution or with an env prefix; or it refuses Claude Code's own read-only commands.
# The refusal is Claude Code's permission check, which no stub can show: the review runs the machine's real Claude
# Code (claudereview() called alone, rvcall), sent to a stub Messages API on this machine that asks for one Bash
# command a turn and keeps each result.
t_reviewast() {
  local claude d=$T/$CASE w=$T/$CASE/cards/c7 out
  claude=$(command -v claude) || fail "this case needs the machine's own Claude Code (claude) on PATH"
  setup "[$(issue 7 2026-01-01)]"
  tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed'
  loop control reviewer claude claude-opus-5-5 max > /dev/null || fail "a Claude reviewer was not accepted"
  # ast-grep installed: the plugin's bin/ast-grep runs the Board's virtualenv's, here one that keeps its arguments and,
  # for a run with -p and -l, prints a hit that names the language and pattern it was given, so the review's result shows
  # the search it asked for reached ast-grep whole; --version succeeds, as reviewtools() asks it whether ast-grep runs.
  # An env prefix's own cb-ast, which would make the file t10.
  export XDG_DATA_HOME=$d/data; mkdir -p "$XDG_DATA_HOME/conveyor/board-venv/bin" "$d/evil" || fail "the fixture could not be made"
  printf '#!/bin/sh\n[ "$1" != --version ] || { echo 0.51.3; exit 0; }\necho "$*" >> %q/ast-args\n[ "$1 $2 $4" = "run -p -l" ] && echo "a.txt:1:AST-HIT lang=$5 pattern=$3"\n' "$d" > "$XDG_DATA_HOME/conveyor/board-venv/bin/ast-grep"
  printf '#!/bin/sh\ntouch %q/t10\n' "$w" > "$d/evil/cb-ast"; chmod +x "$XDG_DATA_HOME/conveyor/board-venv/bin/ast-grep" "$d/evil/cb-ast"
  # Each step: a command (c) and the file in the worktree (p) whose being there after it ran is kept: the file a
  # command that writes would make, or for rm the file it would remove. The checks after the review say which ran.
  jq -n --arg evil "$d/evil" '[
    {c: "cb-ast run -p '\''echo $A'\'' -l bash"}, {c: "git status"}, {c: "ls"},
    {c: "rm a.txt", p: "a.txt"}, {c: "touch t1", p: "t1"}, {c: "bash -c '\''touch t2'\''", p: "t2"},
    {c: "cb-ast run -U -p x -l bash"}, {c: "cb-ast run -p x -l bash && touch t3", p: "t3"},
    {c: "cb-ast run -p x -l bash; touch t4", p: "t4"}, {c: "cb-ast run -p x -l bash || touch t5", p: "t5"},
    {c: "cb-ast run -p x -l bash & touch t6", p: "t6"}, {c: "cb-ast run -p x -l bash | tee t7", p: "t7"},
    {c: "cb-ast run -p x -l bash > t8", p: "t8"}, {c: "cb-ast run -p \"$(touch t9)\" -l bash", p: "t9"},
    {c: ("PATH=" + $evil + ":$PATH cb-ast run -p x -l bash"), p: "t10"}]' > "$d/steps.json" || fail "the steps could not be written"
  # The stub Messages API: a request with tools is answered with the next step's Bash call, as a stream, after the
  # result of the last one is kept in $d/results with whether its file is there now; after the last step, the
  # review's answer ($GO).
  cat > "$d/api.py" <<'PY'
import http.server, json, os, sys
steps, wt, out, go = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3], sys.argv[4]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
        if "count_tokens" in self.path:
            self.send_response(200); self.send_header("content-type", "application/json"); self.end_headers(); self.wfile.write(b'{"input_tokens": 1}'); return
        res = [b for m in body.get("messages", []) if m["role"] == "user" and isinstance(m["content"], list) for b in m["content"] if b.get("type") == "tool_result"]
        if res and body.get("tools"):
            r, s = res[-1], steps[len(res) - 1]
            c = r.get("content"); c = c if isinstance(c, str) else json.dumps(c)
            with open(out, "a") as f:
                f.write(json.dumps({"c": s["c"], "error": bool(r.get("is_error")), "said": c, "there": os.path.exists(os.path.join(wt, s["p"])) if s.get("p") else None}) + "\n")
        n = len(res)
        if body.get("tools") and n < len(steps):
            b = {"type": "tool_use", "id": "s%d" % n, "name": "Bash", "input": {"command": steps[n]["c"], "description": "a step"}}
        else:
            b = {"type": "text", "text": go if body.get("tools") else "ok"}
        self.send_response(200); self.send_header("content-type", "text/event-stream"); self.end_headers()
        def ev(t, d): self.wfile.write(("event: %s\ndata: %s\n\n" % (t, json.dumps(dict(d, type=t)))).encode())
        ev("message_start", {"message": {"id": "m", "type": "message", "role": "assistant", "model": body.get("model"), "content": [], "stop_reason": None, "usage": {"input_tokens": 1, "output_tokens": 1}}})
        if b["type"] == "text":
            ev("content_block_start", {"index": 0, "content_block": {"type": "text", "text": ""}})
            ev("content_block_delta", {"index": 0, "delta": {"type": "text_delta", "text": b["text"]}})
        else:
            ev("content_block_start", {"index": 0, "content_block": dict(b, input={})})
            ev("content_block_delta", {"index": 0, "delta": {"type": "input_json_delta", "partial_json": json.dumps(b["input"])}})
        ev("content_block_stop", {"index": 0})
        ev("message_delta", {"delta": {"stop_reason": "tool_use" if b["type"] == "tool_use" else "end_turn"}, "usage": {"output_tokens": 1}})
        ev("message_stop", {})
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(out + ".port.new", "w").write(str(s.server_address[1])); os.rename(out + ".port.new", out + ".port")
s.serve_forever()
PY
  python3 -I "$d/api.py" "$d/steps.json" "$w" "$d/results" "$GO" & local srv=$!; trap 'kill $srv 2>/dev/null' EXIT
  until [ -s "$d/results.port" ] || ! kill -0 $srv 2>/dev/null; do sleep 0.1; done # the OS picks the port as the server starts: no direct check can know it before then
  [ -s "$d/results.port" ] || fail "the stub Messages API did not start"
  # The machine's real Claude Code, sent to the stub API with a config folder of its own; it keeps its arguments.
  local run; printf -v run '#!/bin/sh\necho "$*" >> %q/args\nexport ANTHROPIC_BASE_URL=http://127.0.0.1:%s ANTHROPIC_API_KEY=k CLAUDE_CONFIG_DIR=%q CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1\nexec %q "$@"\n' \
    "$d" "$(cat "$d/results.port")" "$d/claude-config" "$claude"
  # stub: the real Claude Code's permission check is what this case tests, which the shared stub cannot show
  printf '%s' "$run" > "$STUB/claude" && chmod +x "$STUB/claude" || fail "the claude stand-in could not be written"
  out=$(rvcall 7)
  [ "$(sed -n 2p <<<"$out")" = 'rc=0 GO' ] || fail "the review with ast-grep did not end with its answer: $out $(tail -n 20 "$w.err" 2>/dev/null)"
  [ "$(wc -l < "$d/results")" = "$(jq length "$d/steps.json")" ] || fail "the review did not run each step once: $(cat "$d/results")"
  grep -q -- "--tools Read,Grep,Glob,Bash --allowedTools Bash(cb-ast:\*) --setting-sources  --strict-mcp-config" "$d/args" \
    || fail "the review was not given Bash for cb-ast alone: $(cat "$d/args")"
  local r c
  while IFS= read -r r; do
    c=$(jq -r .c <<<"$r")
    case $c in
      'cb-ast run -p '\''echo $A'\'' -l bash') jq -e '.error == false and (.said | contains("a.txt:1:AST-HIT lang=bash pattern=echo $A"))' <<<"$r" > /dev/null \
        || fail "the review's cb-ast did not get its hits; command: $c; result: $r" ;;
      'git status' | ls) jq -e '.error == false' <<<"$r" > /dev/null || fail "a read-only command Claude Code runs on its own was refused; command: $c; result: $r" ;;
      'rm a.txt') jq -e '.error and .there' <<<"$r" > /dev/null || fail "the review's rm was not refused; command: $c; result: $r" ;;
      *) jq -e '.error and .there != true and (.said | test("AST-HIT") | not)' <<<"$r" > /dev/null || fail "a command that writes was not refused; command: $c; result: $r" ;;
    esac
  done < "$d/results"
  ! grep -q -- '-U' "$d/ast-args" || fail "ast-grep ran with -U (a write option); command: cb-ast run -U -p x -l bash; ast-grep was given: $(cat "$d/ast-args")"
}

# Bugs: with ast-grep installed, a Claude judge keeps no shell while its review has one, is given Bash with no cb-ast on
# its PATH, or is still told it has no shell; or a judge call of another step (the hollow-case check of a build,
# lib/speedproof.sh; the merge of conflicts; the sort of follow-ups) gets the shell too. Its permissions are the
# review's (reviewtools()), whose permission check t_reviewast runs: here judge.test.sh's stub judge (judging(),
# judgeone()) keeps its arguments, prompt and cb-ast's path. The build step's call runs first (JUDGEWRAP), then the review's.
t_judgeast() {
  local f='[P1] a.txt:2 the new line is wrong. Proof: a.txt:2'
  judging "[$(issue 7 2026-01-01)]"
  export XDG_DATA_HOME=$T/$CASE/data; mkdir -p "$XDG_DATA_HOME/conveyor/board-venv/bin" || fail "the fixture could not be made"
  printf '#!/bin/sh\necho 0.51.3\n' > "$XDG_DATA_HOME/conveyor/board-venv/bin/ast-grep" && chmod +x "$XDG_DATA_HOME/conveyor/board-venv/bin/ast-grep"
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'HOLLOW: none' > "$STUB/judge.1"; echo 'F1 ACCEPT: the line is wrong. Cost to every card: none' > "$STUB/judge.2"
  echo 'command -v cb-ast > "$STUB/judge-cbast"' > "$STUB/judge-cmd"
  JUDGEWRAP='CALLSTEP=build judgecall "$wt" "Read the test file." "Test file: a.txt" > /dev/null' judgeone 7 "$STUB/review"
  [ "$(wc -l < "$STUB/judges")" = 2 ] || fail "the build step's judge call and the review's judge did not each run once: $(cat "$STUB/judges" 2>&1)"
  sed -n 1p "$STUB/judges" | grep -q -- '--permission-mode default --tools Read,Grep,Glob --setting-sources  --strict-mcp-config' \
    || fail "a judge call of the build step (CALLSTEP=build) was given more than Read, Grep and Glob: $(sed -n 1p "$STUB/judges")"
  sed -n 2p "$STUB/judges" | grep -q -- '--permission-mode default --tools Read,Grep,Glob,Bash --allowedTools Bash(cb-ast:\*) --setting-sources  --strict-mcp-config' \
    || fail "the review's judge was not given Bash for cb-ast alone: $(sed -n 2p "$STUB/judges")"
  [ "$(cat "$STUB/judge-cbast" 2>&1)" = "${SRC%/*}/bin/cb-ast" ] || fail "the judge's PATH does not hold the plugin's cb-ast: $(cat "$STUB/judge-cbast" 2>&1)"
  grep -q "Your shell runs one command, cb-ast" "$STUB/judge-asked" && ! grep -q 'You have no shell' "$STUB/judge-asked" \
    || fail "the judge is not told it can run cb-ast: $(grep -i shell "$STUB/judge-asked")"
}
