#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The user pages: README.md (the front page), docs/*.md and conveyor/README.md (the engine reference).
# Bugs it catches:
# - tells: a stock AI word of conveyor/rules/ste80.md's word list (§12), an em dash as a clause break (§8), "not just X
#   but Y" or "It's not X, it's Y" (§1) in a page's text (code and code spans aside), named by file and line.
# - names: a command or setting name that a user types, named in backticks by the README before it moved to docs/, is
#   on no page any more (NAMES below; README.md and docs/*.md).
# - leftovers: a page that says how the demo is made (make.sh, "invented project"), or gives the number of cards at once
#   as a fixed number or range, though it is a setting.
# - internals: a second product name ("Conveyor Belt" in text, outside code and URLs: the product is Conveyor), or a
#   name a contributor needs and a user never types (an environment variable CONVEYOR_*, a `.test.` file, a
#   conveyor/lib/ path) on a user page; on the README also "host file", "pack" or "seat", words a new user does not
#   know, and no /units section that links docs/units.md.
# - links: a link in a page to a file or heading that is not there, and a reference in any tracked file to a README or
#   docs page heading ("conveyor/README.md, The test step", "docs/setup.md, Run") whose heading is gone.
# Then fixtures: a paragraph with three tells, a page set missing one name, a page with each leftover and a dead
# reference, and a front page and a docs page with each internal must each fail, naming what failed.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
W=$(mktemp -d) || exit 1; trap 'rm -rf "$W"' EXIT
git -C "$SRC" ls-files -co --exclude-standard > "$W/files" || { echo "FAIL [pages]: git cannot list the files" >&2; exit 1; }
# The command and setting names a user types that the README named before the move (issue 622), one a line.
cat > "$W/names" <<'EOF'
/conveyor-belt:setup
/conveyor-belt:setup --foreman
/conveyor-belt:setup --survey
/conveyor-belt:foreman
/conveyor-belt:foreman off
/conveyor-belt:away
/conveyor-belt:review
/conveyor-belt:review [base] [focus]
/conveyor-belt:plan
/conveyor-belt:plan <what you want to do>
/conveyor-belt:auto
/conveyor-belt:auto on | narrow | off
/plugin
/plugin marketplace update conveyor-belt
/plugin uninstall conveyor-belt@conveyor-belt
gh auth login
gh issue view --repo
npm install -g @anthropic-ai/claude-code
npm install -g @openai/codex
npm install -g opencode-ai
claude plugin install mattpocock-skills@claude-plugins-official
brew install bash jq coreutils findutils gnu-sed grep flock
opencode auth login
opencode models
codex debug models
ssh -o BatchMode=yes <target> true
systemctl --user disable --now conveyor-machine.service
launchctl bootout gui/$(id -u)/conveyor-machine
systemctl --user disable --now dashboard.service
launchctl bootout gui/$(id -u)/com.conveyor.dashboard
conveyor.sh board
conveyor doctor
conveyor.sh
conveyor.sh auto decide
conveyor.sh clis
conveyor.sh control
conveyor.sh control cap off
conveyor.sh control dep-guard off
conveyor.sh control depends
conveyor.sh control depends <issue> remove <N>
conveyor.sh control force <issue>
conveyor.sh control hold <issue>...
conveyor.sh control judge on
conveyor.sh control judge opencode openrouter/<model>
conveyor.sh control model|reviewer|judge <cli> <model> [effort]
conveyor.sh control release
conveyor.sh control release <issue>...
conveyor.sh control reviewer opencode openrouter/<model> high
conveyor.sh flaky add <case> <source> <note>
conveyor.sh install <commit>
conveyor.sh lane ... create
conveyor.sh lane fast create
conveyor.sh lane fast review
conveyor.sh lane research create
conveyor.sh machine
conveyor.sh machine pause
conveyor.sh release-prep <version>
conveyor.sh retry
conveyor.sh retry <issue>
conveyor.sh shut
conveyor.sh test-settings
conveyor.sh testrules
conveyor.sh wording adversarial|review
control [<action>]
control depends
control force
dep-guard on
model default
declined add <card> <issue> <code | judge | owner> <why> <finding>
declined build <id>
declined dismiss [--by <who>] <id>...
doctor
foreman [--new] [<claude argument>...]
flaky add <case> <source> <note>
flaky off
full-test
full-test push
full-test anyway <run id> [--by <who>]
gh-write <gh arguments>
github <folder>
health
history
cards
check
install <commit>
install-service
land-branch <branch>
lane fast create | review | land | reset [--drop <sha>]
lane fast land
lane fast reset
lane fast review
lane research create
machine
machine pause
machine resume
main-test
pick --dry --issues <file> --state <dir>
product <commit>
pushable
release-prep <version>
retry <card id>
retry <issue>
run [--only <issue>[,<issue>...]] [max-cards]
serve
setup
setup --survey yes
setup [--owner <name>] [--product <path>]... [--test <command>] [--survey yes|no] [--test-patterns yes|no] [--test-list yes|no] [--test-map yes|no] --fast-lane yes|no --research-lane yes|no [--pin] [--foreman]
shut <card id>
shut <issue>
snapshot
state-dir
survey
take
test-settings
testaction <judge | explain> <test file>
testaction stop <id>
testissue <test file> <title> <body>
watch
max-cards
--only
--new
--pin
--model
opus
cap
maxLoad
minFreeMemMB
testSlots
"mode": "pause"
claudeProxy
models.claudeProxy
models.allowed
models.allowed["codex-builder"]
auto.reserved
review.proof
review.wording
defaultBranch
pipelineFiles
plugin
plugin.commit
test.firstSurvey
test.full
test.main
test.survey
tunables.pushRetry
foreman.away
host
ssh
main
records
ledger
lanes
{"follow": "releases"}
{"follow": "main"}
{"commit": "<that id>"}
{"records": [{"repo": "<name>", "main": "<its main checkout>"}]}
public
private
any
real
P3
check
transport
narrow
on
default
TESTRUN cases=N
cases/ok
cases/failed
Depends on: #N
Depends on:
Visible change approved:
owner/repo#N
opencode:<provider>/<model>
<provider>/<model>
claude
codex
opencode
codex-builder
claude-reviewer
mattpocock-skills
flock
gh
openssl
req
-addext
~/.config/conveyor/host.json
~/.config/opencode/opencode.json
config.toml
.conveyor/project.json
.conveyor/card-rules.md
.conveyor/
.claude/settings.json
shim.sh
$XDG_DATA_HOME
## Done when
D<n> met:
D<n> not met:
UNPROVEN:
ok:
missing:
conveyor-machine
conveyor-cards
conveyor-cards-<repo>
conveyor-cards-<repo>-2
conveyor/state
<state folder>/auto/<date>-<time>.md
conveyor/schema/pack.schema.json
conveyor/privacy/check.sh
conveyor/rules/review.md
docs/releases/<version>.md
conveyor/release-suite
EOF

python3 -I - "$SRC" "$W" <<'PYEOF'
import os, re, sys

src, work = sys.argv[1], sys.argv[2]
names = [l.rstrip("\n") for l in open(os.path.join(work, "names"), encoding="utf-8") if l.strip()]
tracked = [l.rstrip("\n") for l in open(os.path.join(work, "files"), encoding="utf-8") if l.strip()]

# The tells ste80.md lists that text alone shows: its §12 word list (with their inflections), a dash as a clause break
# (§8: an em dash, or an en dash or a double hyphen between words), and the two §1 shapes.
STOCK = "delve|leverage|robust|seamless|crucial|pivotal|showcase|underscore|tapestry|testament|landscape|additionally|utilize|meticulous|intricate"
TELLS = [
    ("a stock AI word", re.compile(r"\b(?:%s)(?:s|d|ed|es|ing|ly|ness|ation)?\b" % STOCK, re.I)),
    ("a dash as a clause break", re.compile("—|\\w – \\w|\\w -- \\w")),
    ('"not just X but Y"', re.compile(r"\bnot (?:just|only|merely|simply)\b[^.!?]{0,120}?\bbut\b", re.I)),
    ("\"It's not X, it's Y\"", re.compile(r"\b(?:it|this|that)(?:'s|’s| is) not\b[^.!?]{0,120}?[,;:]\s*(?:it|this|that)(?:'s|’s| is)\b", re.I)),
]

def prose(text):
    """Each line of a Markdown text, with fenced blocks blanked and code spans emptied."""
    out, fence = [], False
    for line in text.split("\n"):
        if re.match(r"\s*(```|~~~)", line):
            fence = not fence
            out.append("")
        else:
            out.append("" if fence else re.sub(r"`[^`]*`", "``", line))
    return out

def tells(name, text):
    return ["%s:%d: %s: %s" % (name, i, what, m.group(0))
            for i, line in enumerate(prose(text), 1) for what, rx in TELLS for m in rx.finditer(line)]

def spans(text):
    """The backticked spans of a Markdown text, fenced blocks aside, a span's line breaks read as spaces."""
    text = re.sub(r"(?ms)^\s*```.*?^\s*```", "", text)
    return {re.sub(r"\s+", " ", s).strip() for s in re.findall(r"`([^`]+)`", text)}

def missing_names(texts):
    have = set().union(*(spans(t) for t in texts))
    out = []
    for n in names:
        if n in have or (" " in n and any(n in s for s in have)):
            continue
        out.append(n)
    return out

def leftovers(name, text):
    out = []
    for i, line in enumerate(text.split("\n"), 1):
        for w in ("make.sh", "invented project"):
            if w in line.lower():
                out.append("%s:%d: says how the demo is made (%s)" % (name, i, w))
    # A sentence that gives the cards at once a number: it is a setting (the Rules tab, `conveyor.sh control cap`).
    # Sentences are read within a paragraph or a list item, their wrapped lines joined.
    items = re.split(r"\n\s*\n|\n\s*(?:[-*]|\d+\.) ", text)
    for sentence in (s for i in items for s in re.split(r"(?<=[.!?])\s+", re.sub(r"\s+", " ", i))):
        if re.search(r"cards at once", sentence, re.I) and re.search(r"\d", re.sub(r"`[^`]*`", "", sentence)):
            out.append("%s: gives cards at once a fixed number: %s" % (name, sentence[:160]))
    return out

def internals(name, text, front):
    """A second product name in a page's text, a contributor's name anywhere in it, and on the front page (front) the
    internal words and a missing /units section."""
    out = []
    for i, line in enumerate(prose(text), 1):
        line = re.sub(r"\]\([^)]*\)|(?:src|srcset|href)=\"[^\"]*\"|https?://\S+", "", line)
        for m in re.finditer(r"\bConveyor[ -]Belt\b", line, re.I):
            out.append("%s:%d: names the product %s, not Conveyor" % (name, i, m.group(0)))
    for i, line in enumerate(text.split("\n"), 1):
        for m in re.finditer(r"CONVEYOR_[A-Z_]+|[\w./*-]+\.test\.\w+|conveyor/lib/[\w./-]*", line):
            out.append("%s:%d: names %s, which a user does not need" % (name, i, m.group(0)))
        if front:
            for m in re.finditer(r"\bhost files?\b|\bpacks?\b|\bseats?\b", line, re.I):
                out.append("%s:%d: says %s, a word a new user does not know" % (name, i, m.group(0)))
    if front and not re.search(r"(?ms)^## /units\n(?:(?!^## ).)*\]\(docs/units\.md\)", text):
        out.append("%s: has no /units section that links docs/units.md" % name)
    return out

def slug(h):
    return re.sub(r" ", "-", re.sub(r"[^\w\- ]", "", h.strip().lower()))

def headings(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return None
    text = re.sub(r"(?ms)^\s*```.*?^\s*```", "", text)
    return [h.strip() for h in re.findall(r"^#{1,6} +(.+?)\s*#*\s*$", text, re.M)]

def dead_links(root, rel):
    """Each link or image of a page to a file of the repository that is not there, or to a heading that is not."""
    text = open(os.path.join(root, rel), encoding="utf-8").read()
    text = re.sub(r"(?ms)^\s*```.*?^\s*```", "", re.sub(r"`[^`\n]*`", "", text))
    out = []
    for t in re.findall(r"\]\(([^)\s]+)\)|(?:src|href)=\"([^\"]+)\"", text):
        t = t[0] or t[1]
        if re.match(r"(https?:|mailto:)", t):
            continue
        f, _, anchor = t.partition("#")
        target = os.path.normpath(os.path.join(os.path.dirname(rel), f)) if f else rel
        if not os.path.exists(os.path.join(root, target)):
            out.append("%s: links %s, which is not there" % (rel, t))
        elif anchor and anchor not in [slug(h) for h in headings(os.path.join(root, target)) or []]:
            out.append("%s: links %s, and %s has no such heading" % (rel, t, target))
    return out

REF = re.compile(r"(?P<top>the top )?`?(?P<path>(?:conveyor/)?README\.md|docs/[\w-]+\.md)`?, (?=[A-Z])")

def dead_refs(root, rel):
    """Each reference in a file to a heading of a README or a docs page ("README.md, Run") that the page lacks. The
    words after the comma, read across a line break and the comment marks that start the next line, must start with
    one of the page's headings."""
    try:
        text = open(os.path.join(root, rel), encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        return []
    out = []
    for m in REF.finditer(text):
        p = m.group("path")
        if p == "README.md" and not m.group("top") and rel.startswith("conveyor/"):
            p = "conveyor/README.md"  # a bare README.md in the engine is the engine's
        hs = headings(os.path.join(root, p))
        after = re.sub(r"\s*\n\s*(?:#|//|\*)?\s*", " ", text[m.end():m.end() + 200])
        if hs is None or not any(after.startswith(h) and not after[len(h):len(h) + 1].isalnum() for h in hs):
            line = text.count("\n", 0, m.start()) + 1
            words = re.match(r"[^.,;:()\"`]*", after).group(0).strip()
            out.append("%s:%d: names the heading \"%s\" of %s, which has none such" % (rel, line, words, p))
    return out

def pages(root):
    docs = sorted("docs/" + f for f in os.listdir(os.path.join(root, "docs")) if f.endswith(".md"))
    return ["README.md"] + docs

fails = []
user = pages(src)
every = user + ["conveyor/README.md"]
texts = {p: open(os.path.join(src, p), encoding="utf-8").read() for p in every}
for p in every:
    fails += tells(p, texts[p]) + leftovers(p, texts[p]) + dead_links(src, p)
for p in user:
    fails += internals(p, texts[p], p == "README.md")
fails += ["no page names %s" % n for n in missing_names([texts[p] for p in user])]
for rel in tracked:
    if rel == "README-pages.test.sh" or rel.endswith((".gif", ".mp4", ".svg", ".png", ".lock", "package-lock.json")):
        continue
    fails += dead_refs(src, rel)

# The fixtures: each must fail, naming what failed.
para = ("Conveyor is not just a loop, but a whole way of working.\n"
        "It delves into each issue — and every card lands.\n")
got = tells("fixture.md", para)
if len(got) != 3 or not all(g.startswith(("fixture.md:1:", "fixture.md:2:")) for g in got):
    fails.append("a paragraph with three tells gave %d, not three named by file and line: %s" % (len(got), got))
got = missing_names(["`%s`" % n for n in names if n != "maxLoad"])
if got != ["maxLoad"]:
    fails.append("a page set without `maxLoad` reported %s, not maxLoad alone" % got)
fx = os.path.join(work, "fx")
os.makedirs(os.path.join(fx, "docs"))
open(os.path.join(fx, "README.md"), "w").write("# Fixture\n\n## Run\n\nSee [setup](docs/setup.md#gone).\n")
open(os.path.join(fx, "docs", "setup.md"), "w").write(
    "# Setup\n\nIt is made from an invented project, by `docs/demo/make.sh`.\n"
    "Cards at once go from 3 to 6. See docs/setup.md, Gone heading.\n")
got = leftovers("docs/setup.md", open(os.path.join(fx, "docs", "setup.md")).read())
got += dead_links(fx, "README.md") + dead_refs(fx, "docs/setup.md") + dead_refs(fx, "README.md")
want = ["(make.sh)", "(invented project)", "fixed number", "has no such heading", "\"Gone heading\""]
if len(got) != len(want) or not all(any(w in g for g in got) for w in want):
    fails.append("the leftovers fixture gave %s, not one failure for each of %s" % (got, want))
# Bug (#635): user pages said "Conveyor Belt" beside "Conveyor", named the engine's environment variables, test
# files and lib/ paths, and the front page used the internal words and had no /units section.
got = internals("README.md", "# Conveyor Belt\n\nSet `CONVEYOR_MAIN`. Run `hooks/units-fetch.test.sh`.\n"
                "Setup writes the host file and the pack. Each seat has a model.\n"
                "See [it](https://example.com/conveyor-belt) and `conveyor-belt@conveyor-belt`.\n\n## /units\n\nIt shows the belt.\n", True)
want = ["Conveyor Belt", "CONVEYOR_MAIN", "units-fetch.test.sh", "host file", "pack,", "seat,", "no /units section"]
if len(got) != len(want) or not all(any(w in g for g in got) for w in want):
    fails.append("the internals fixture gave %s, not one failure for each of %s" % (got, want))
got = internals("docs/x.md", "Edit `conveyor/lib/x.sh`. The pack and the host file hold it. See [/units](units.md).\n", False)
if len(got) != 1 or "conveyor/lib/x.sh" not in got[0]:
    fails.append("a docs page with a conveyor/lib/ path gave %s, not that path alone" % got)

for f in fails:
    print("FAIL [pages]: " + f, file=sys.stderr)
if fails:
    sys.exit(1)
print("ok pages")
PYEOF
