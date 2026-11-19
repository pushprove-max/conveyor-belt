#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Release 1's file set, computed (plan docs/plans/conveyor-plugin-2026-11-10.md, section 11): from the entry points
# below it follows every file a file reaches (a source or `.`, a script it calls, a file it reads, a Python import, a
# page's script or style) and prints the whole set, one path per line, relative to the checkout, sorted.
# Usage: closure.sh [<checkout>]   (default: the checkout holding this script; a git repository, whose tracked files
# are the only ones a reference can name). Exit 1 when an entry point is not a tracked file, or a file of the set is
# missing from the checkout (closure.test.sh removes each one in turn and expects this).
# A file is reached only by a path anchored at a known place: the referring file's own folder ($(dirname "$0"),
# BASH_SOURCE, __file__, import.meta.url, and a variable holding one of them) or the checkout's top
# (git rev-parse --show-toplevel). A bare path such as 'src/x.ts' is the user's repository's, not ours (a hook's test
# input, a check's pattern), and a path in a comment, a document or a data file is for its reader; neither is
# followed. A file a table names (TABLES, below: the command table, SNAPLIBS, FETCH) is required: a missing or
# untracked one fails, naming the file that holds the table, the name and the path it expects. The project pack (the
# .conveyor/ folder: the host project's input, read at run time), the area rule files and the startup instructions stay in the host project (section 11): a reference to one is never followed. A page's relative
# src/href/import, an ES module's relative import (a test's shared helper) and a Python import resolve from the file's
# folder. closure.test.sh
# copies exactly this set into an empty directory and runs the hooks, the Board and the engine tests from there: a
# reference this misses fails that test.
# closure.sh --unreached [<checkout>] prints, in place of the set, each tracked file of the engine and the Board
# (conveyor/, .claude/dashboard/, .claude/scripts/dashboard*; not a test file, *.test.*, nor what stays in the host
# project) that the set misses and the left-out list below does not name. closure.test.sh runs it first, and fails
# its cases that copy the set on any such file in seconds, before a test runs from the copy.
set -euo pipefail
UNREACHED=''; [ "${1:-}" != --unreached ] || { UNREACHED=1; shift; }
ROOT=$(cd "${1:-$(dirname "$0")/../..}" && pwd -P)

# The entry points: the engine, the Board (its scripts and its page), the release-1 card hooks and every test file of
# those parts (a hook's tests are the __tests__ files named after it). Setup, doctor and install do not exist yet
# (Phase C).
ENTRY=(
  conveyor/conveyor.sh conveyor/report.sh conveyor/watch.py conveyor/privacy/check.sh
  conveyor/schema/pack.schema.json conveyor/tools/closure.sh
  'conveyor/*.test.sh' 'conveyor/lib/*.test.sh' 'conveyor/tools/*.test.sh'
  '.claude/dashboard/*' .claude/scripts/dashboard.sh .claude/scripts/dashboard_server.py
  .claude/scripts/dashboard_stream.py .claude/scripts/dashboard_limit.py .claude/scripts/dashboard_alerts.jq
  .claude/scripts/decision.sh '.claude/scripts/__tests__/dashboard*.test.*' '.claude/scripts/__tests__/decision*.test.*'
)
HOOKS=(git-safety bash-guardrails bash-write-rules file-size-cop dependency-addition-guard new-test-file-guard
  bugfix-test-lock suite-rerun-guard literal-secret-warning adversarial-review-gate)
# The plugin's hooks: hooks/hooks.json runs each one through shim.sh, so both ship, and so does every hook it names.
ENTRY+=(shim.sh hooks/hooks.json)
# The /units pane: its FETCH (a table, below) names the fetch it runs, which the engine's Board cases run from the
# install too.
ENTRY+=(hooks/units.tsx)
# Foreman mode: the hooks its setup writes run its scripts through the shim, and they reach one another through
# lib.sh's FHERE, which is not followed, so the whole folder ships, with the plugin commands that set it up (its test
# checks them for private names).
ENTRY+=('conveyor/foreman/*' 'commands/*.md')
# A missing hooks.json is named by the check of the set below.
[ ! -f "$ROOT/hooks/hooks.json" ] || HOOKS+=($(jq -r '.hooks[][].hooks[].command' "$ROOT/hooks/hooks.json" | sed -n 's|.*/shim\.sh \.claude/hooks/\([^ /]*\)\.sh.*|\1|p'))
for h in "${HOOKS[@]}"; do ENTRY+=(".claude/hooks/$h.sh" ".claude/hooks/__tests__/$h.*" ".claude/hooks/__tests__/$h-*"); done

# What section 11 keeps in the host project that a release-1 file names (a hook reads the project's rules, the engine the
# project's pack folder, .conveyor/, a test the project's startup text). The tests read a pack of their own, conveyor/lib/test-pack.json, so
# they run where no project pack is. The pack's hooks.json is not read for hooks: they are the project's product hooks.
STAYS=('.claude/rules/*' '.claude/commands/*' '.conveyor/*' AGENT_STARTUP.md CLAUDE.md)
# The left-out list: files of the engine and the Board the release does not ship, on purpose. Each is a pattern and
# the reason it is left out, a pair a line.
LEFT_OUT=(
  'conveyor/tests/speed/*' "the test speed survey: notes for this repository's developers, which no engine or Board file reads"
)
LEFT=''
for ((i = 0; i < ${#LEFT_OUT[@]}; i += 2)); do
  [ -n "${LEFT_OUT[i + 1]:-}" ] || { echo "closure: a left-out file has no reason: ${LEFT_OUT[i]}" >&2; exit 1; }
  LEFT+="${LEFT_OUT[i]} "
done

cd "$ROOT"
git ls-files -z | STAYS="${STAYS[*]}" LEFT="$LEFT" UNREACHED="$UNREACHED" python3 -I -c '
import os, re, sys
from fnmatch import fnmatchcase
stays = os.environ["STAYS"].split()
files = set(f for f in sys.stdin.read().split("\0") if f and not any(fnmatchcase(f, x) for x in stays))
dirs = set(os.path.dirname(f) for f in files)
entries, missing = [], []
for e in sys.argv[1:]:
    hit = sorted(f for f in files if fnmatchcase(f, e)) if "*" in e else ([e] if e in files else [])
    if not hit and "*" not in e: missing.append(e)
    entries += hit
if missing:
    sys.exit("closure: entry point not a tracked file: " + " ".join(missing))

def norm(p):
    p = os.path.normpath(p)
    return "." if p == "." else (None if p.startswith("..") else p)

def mk(p):
    p = norm(p)
    return "@@D:%s@@" % p if p else "@@D:..@@"

M = r"@@D:([^@]*)@@"
Q = r"[\x27\"]([^\x27\"]*)[\x27\"]"
# Expressions that name the folder of the file (HERE) or the top of the checkout.
SELF = [r"\$\(dirname (?:-- )?\"(?:\$0|\$\{BASH_SOURCE\[0\](?::-\$0)?\}|\$\(readlink -f \"\$\{BASH_SOURCE\[0\]\}\"\))\"\)",
        r"\$\{BASH_SOURCE\[0\]%/\*\}", r"\$\{0%/\*\}",
        r"os\.path\.dirname\(os\.path\.(?:abspath|realpath)\(__file__\)\)", r"os\.path\.dirname\(__file__\)",
        r"Path\(__file__\)\.resolve\(\)\.parent\b(?!s)", r"path\.dirname\(fileURLToPath\(import\.meta\.url\)\)"]
SELF = re.compile("|".join(SELF))
TOP = re.compile(r"\$\(git (?:-C \"[^\"]*\" )?rev-parse --show-toplevel[^)]*\)")
PARENTS = re.compile(r"Path\(__file__\)\.resolve\(\)\.parents\[(\d)\]")
URL = re.compile(r"(?:fileURLToPath\()?new URL\(" + Q + r", import\.meta\.url\)\)?")
QS = re.compile(Q)
# The steps that carry a known place along a path, each with what its match needs (None: only a known place), which
# is found far faster than the match: a text without it is not scanned.
STEPS = [
    (None, re.compile(M + r"(\"?)(/[\w.@/-]*[\w@-]|/\.\.(?:/\.\.)*)"), lambda m: mk(m.group(1) + m.group(3)) + m.group(2)),
    (re.compile(r"join\(\s*@@D:"), re.compile(r"(?:os\.)?(?:path\.)?join\(\s*" + M + r"((?:\s*,\s*" + Q + r")+)\s*\)"),
     lambda m: mk(os.path.join(m.group(1), *QS.findall(m.group(2))))),
    (None, re.compile(M + r"((?:\s*/\s*" + Q + r")+)"), lambda m: mk(os.path.join(m.group(1), *QS.findall(m.group(2))))),
    (re.compile(r"\$\(cd "), re.compile(r"\$\(cd (?:-P )?(?:-- )?\"" + M + r"\"(?: 2>/dev/null)? && pwd(?: -P)?\)"), lambda m: mk(m.group(1))),
    (re.compile(r"\$\(dirname "), re.compile(r"\$\(dirname (?:-- )?\"" + M + r"\"\)"), lambda m: mk(os.path.dirname(m.group(1)) or ".")),
    (re.compile(r"\$\{CLAUDE_PROJECT_DIR:-@@D:"), re.compile(r"\$\{CLAUDE_PROJECT_DIR:-" + M + r"\}"), lambda m: mk(m.group(1))),
    (re.compile(r"str\(@@D:"), re.compile(r"\bstr\(" + M + r"\)"), lambda m: mk(m.group(1))),
]
PYVAR = re.compile(r"^\s*(?:const |let |var )?([A-Za-z_]\w*)\s*=\s*" + M + r"\s*;?\s*$", re.M)
SHVAR = re.compile(r"(?:^|[\s;&|(])(?:export |local |readonly )?([A-Za-z_]\w*)=\"?" + M + r"\"?(?=$|[\s;&|)])", re.M)

def rewrite(text, here, py):
    text = SELF.sub(mk(here), text)
    text = TOP.sub(mk("."), text)
    text = PARENTS.sub(lambda m: mk(os.path.join(here, *[".."] * (int(m.group(1)) + 1))), text)
    if "import.meta.url" in text:
        text = URL.sub(lambda m: mk(os.path.join(here, m.group(1))), text)
    # A text with no known place (a bundled library) has nothing to carry: it is not rescanned.
    for _ in range(6 if "@@D:" in text else 0):
        was = text
        for need, rx, fn in STEPS:
            if need is None or need.search(text):
                text = rx.sub(fn, text)
        # A variable that holds a known place stands for it wherever it is read.
        if py:
            # Not filtered to lines with a place: an assignment may break after its = (const base =\n...).
            for name, loc in PYVAR.findall(text):
                # The name first, so it is searched for as a literal; what precedes it is checked after.
                text = re.sub(name + r"(?<![\w.$@]" + name + r")\b(?!\s*=[^=])", mk(loc), text)
        else:
            # Each name its first place, all read in one pass (a place written in holds no $, so none is read twice).
            # A shell assignment is on one line, so only the lines that hold a place are searched for one.
            held = "\n".join(l for l in text.split("\n") if "@@D:" in l)
            locs = {}
            for name, loc in SHVAR.findall(held):
                locs.setdefault(name, mk(loc))
            if locs:
                alt = "|".join(locs)
                text = re.sub(r"\$(?:\{(" + alt + r")\}|(" + alt + r")\b)", lambda m: locs[m.group(1) or m.group(2)], text)
        if text == was:
            break
    return text

# The tables that name files the code reaches by a path built at run time: the file that holds one, its name, the
# line that names its entries (each word of the value one entry), and the path an entry stands for. The command table
# of conveyor.sh (each line `cmd <command> <script>`), the libraries the snapshot loads (SNAPLIBS: those, not the
# whole lib/ folder) and the fetch the /units pane runs (FETCH, from the plugin root).
TABLES = {
    "conveyor/conveyor.sh": ("cmd", r"^cmd \S+ (\S+)", "conveyor/commands/%s"),
    "conveyor/commands/snapshot.sh": ("SNAPLIBS", r"^SNAPLIBS=[\x27\"]([^\x27\"]*)[\x27\"]", "conveyor/lib/%s.sh"),
    "hooks/units.tsx": ("FETCH", r"^const FETCH = [\x27\"]([^\x27\"]*)[\x27\"]", "%s"),
}

def refs(path):
    if not os.path.isfile(path):
        sys.exit("closure: a file of the set is missing: " + path)
    out = set()
    if path in TABLES:
        name, rx, at = TABLES[path]
        vals = re.findall(rx, open(path, encoding="utf-8").read(), re.M)
        if not vals:
            sys.exit("closure: %s: its %s table names no file" % (path, name))
        for s in (s for v in vals for s in v.split()):
            if norm(at % s) not in files:
                sys.exit("closure: %s: %s names %s, but %s is missing or untracked" % (path, name, s, at % s))
            out.add(norm(at % s))
    ext = os.path.splitext(path)[1]
    if ext not in (".sh", ".py", ".jq", ".js", ".mjs", ".cjs", ".html", ".css", ".service", ""):
        return out
    try:
        text = open(path, encoding="utf-8").read()
    except UnicodeDecodeError:
        return out
    here = os.path.dirname(path)
    if ext in (".sh", ".py", ".jq", ".service", ""):
        text = "\n".join(l for l in text.split("\n") if not l.lstrip().startswith("#"))
    # The parts of the engine (conveyor/lib/*.sh) and the scripts of its commands (conveyor/commands/*.sh), sourced
    # by conveyor.sh, read HERE as it sets it: the engine folder.
    if re.fullmatch(r"conveyor/(?:lib|commands)/[^/]+\.sh", path) and ".test." not in path:
        text = "HERE=" + mk("conveyor") + "\n" + text
    # The line of conveyor.sh that sources the script of the given command by name reads the one script its command
    # table names (TABLES), not the whole folder.
    if path == "conveyor/conveyor.sh":
        text = text.replace(". \"$HERE/commands/$CMD_RUN\"", "")
    text = rewrite(text, here, ext in (".py", ".js", ".mjs", ".cjs"))
    # A file the code first tests for ([ -e x ] || skip, [ ! -e x ] || run x) is optional, so not followed; but not one
    # whose absence stops the code ([ -f x ] || exit 1, [ ! -e x ] && fail ...), which is required.
    stop = r"\s*(?:\{[^}]*?)?\b(?:exit(?!\s+0\b)|fail|die)\b"
    opt = set(m.group(2) for m in re.finditer(r"\[\s+(!\s+)?-[ef]\s+\"?" + M + r"\"?\s*\]\s*(\|\||&&)?", text)
              if not re.match(stop, text[m.end():]) or m.group(3) != ("&&" if m.group(1) else "||"))
    test = ".test." in os.path.basename(path)
    # A folder on sys.path gives imports, followed below, not its files.
    paths = [here] + re.findall(r"sys\.path\.insert\(\s*\d+\s*,\s*" + M, text)
    text = re.sub(r"sys\.path\.insert\(\s*\d+\s*,\s*" + M, "", text)
    for m in re.finditer(M, text):
        loc = m.group(1)
        if loc in opt:
            continue
        if loc in files:
            out.add(loc)
        # A folder a program reads holds its files (a test links or copies a folder whole as a fixture). A file of a
        # folder named at run time ("$HERE/lib/$l.sh") is one file, not the folder: it is not followed.
        elif loc in dirs and not test and not (here + "/").startswith(loc + "/") and loc != "." \
                and not re.match(r"\"?/\$", text[m.end():]):
            out.update(f for f in files if os.path.dirname(f) == loc)
    if ext in (".html", ".css", ".js", ".mjs"):
        for m in re.finditer(r"(?:\b(?:src|href)=|\bfrom\s+|\bimport\s*\(\s*|\burl\(\s*)" + Q, text):
            p = norm(os.path.join(here, m.group(1).split("?")[0]))
            if p in files: out.add(p)
    # A Python import: the folder of the file, and every folder the file puts on sys.path.
    for m in re.finditer(r"^\s*(?:from\s+([\w.]+)\s+import|import\s+([\w., ]+))", text, re.M):
        for mod in (m.group(1) or m.group(2)).split(","):
            mod = mod.strip().split(" ")[0].replace(".", "/")
            for b in paths:
                p = norm(os.path.join(b, mod + ".py"))
                if p in files:
                    out.add(p); break
    return out

seen, todo = set(entries), list(entries)
while todo:
    for r in refs(todo.pop()):
        if r not in seen:
            seen.add(r); todo.append(r)
if os.environ["UNREACHED"]:
    left = os.environ["LEFT"].split()
    seen = set(f for f in files - seen if re.match(r"conveyor/|\.claude/dashboard/|\.claude/scripts/dashboard[^/]*$", f)
               and ".test." not in os.path.basename(f) and not any(fnmatchcase(f, x) for x in left))
sys.stdout.write("".join(f + "\n" for f in sorted(seen)))
' "${ENTRY[@]}"
