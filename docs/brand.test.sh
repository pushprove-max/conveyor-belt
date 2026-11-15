#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The README's header: the Board's brand, docs/brand.svg (and docs/brand-dark.svg for GitHub's dark theme), as the
# Board's header draws it: the tile, the word "Conveyor" and the belt with a roller at each end.
# Bugs: the README's first picture is not the brand (the lone tile, or a badge, comes first); a dark-theme source
# that is not the dark brand; the word drawn as <text>, which a reader without the Board's font sees in another face;
# a tile that is not the Board's tile; a belt missing, or not two rollers at its two ends; a script in the file;
# a badge row that names the reviewer CLIs ("reviewer: ...") in place of the harnesses Conveyor runs on, for building
# and reviewing alike, or a harness badge (its alt text or its picture) that leaves out Claude Code, Codex or OpenCode.
set -uo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd -P)
python3 -I - "$SRC" <<'EOF' && echo "ok brand"
import re, sys
import xml.etree.ElementTree as ET

def fail(why):
    print("FAIL [brand]: " + why, file=sys.stderr)
    sys.exit(1)

src = sys.argv[1]
NS = "{http://www.w3.org/2000/svg}"
tag = lambda el: el.tag[len(NS):] if el.tag.startswith(NS) else el.tag
cls = lambda el: el.get("class", "").split()

def shapes(root):
    return [(tag(el), el.get("d"), el.get("rx")) for el in root.iter() if tag(el) in ("rect", "path")]

# The Board's tile, as docs/logo.svg holds it.
logo = ET.parse(src + "/docs/logo.svg").getroot()

def check(rel):
    try:
        root = ET.parse(src + "/" + rel).getroot()
    except (OSError, ET.ParseError) as e:
        fail("%s cannot be read as XML: %s" % (rel, e))
    every = list(root.iter())
    if any(tag(el) in ("script", "foreignObject") for el in every) or \
            any(k.lower().startswith("on") for el in every for k in el.attrib):
        fail("%s holds a script" % rel)
    if any(tag(el) == "text" for el in every):
        fail("%s draws text with <text>, not as paths" % rel)
    tiles = [el for el in every if "tile" in cls(el)]
    if len(tiles) != 1 or shapes(tiles[0]) != shapes(logo):
        fail("%s does not hold the Board's tile (the shapes of docs/logo.svg)" % rel)
    words = [el for el in every if tag(el) == "path" and "word" in cls(el)]
    # "Conveyor" in outline: C, o (2), n, v, e (2), y, o (2), r; 11 closed shapes.
    if len(words) != 1 or len(re.findall(r"[Mm]", words[0].get("d", ""))) != 11:
        fail("%s does not draw the word Conveyor as one path of 11 outlines" % rel)
    belts = [el for el in every if "belt" in cls(el)]
    bands = [r for b in belts for r in b.iter(NS + "rect")]
    if len(belts) != 1 or not bands:
        fail("%s has no belt" % rel)
    left = float(bands[0].get("x")); right = left + float(bands[0].get("width"))
    rollers = [el for el in every if "roller" in cls(el)]
    ends = sorted(float(c.get("cx")) for r in rollers for c in r.iter(NS + "circle"))
    if len(rollers) != 2 or len(ends) != 2 or abs(ends[0] - left) > 3 or abs(ends[1] - right) > 3:
        fail("%s has not one roller at each end of its belt (belt %g to %g, rollers at %s)" % (rel, left, right, ends))
    if root.find(NS + "title") is None:
        fail("%s has no title for a screen reader" % rel)

readme = open(src + "/README.md", encoding="utf-8").read()
first = re.search(r"<img\b[^>]*>", readme)
if not first or 'src="docs/brand.svg"' not in first.group(0):
    fail("the README's first picture is not docs/brand.svg: %s" % (first.group(0) if first else "none"))
check("docs/brand.svg")
pic = re.search(r"<picture>(.*?)</picture>", readme, re.S)
if pic and first.start() > pic.start():
    dark = re.search(r'<source\s+media="\(prefers-color-scheme:\s*dark\)"\s+srcset="([^"]+)"', pic.group(1))
    if not dark or dark.group(1) != "docs/brand-dark.svg":
        fail("the header's dark-theme source is not docs/brand-dark.svg")
    check("docs/brand-dark.svg")

# The badge row: one harness badge naming the three CLIs Conveyor runs on, and no reviewer badge.
from urllib.parse import unquote
badges = [(unquote(m.group(1)), m.group(2)) for m in
          re.finditer(r'<img\s+src="(https://img\.shields\.io/[^"]+)"\s+alt="([^"]*)"', readme)]
if any("reviewer" in s.lower() or "reviewer" in a.lower() for s, a in badges):
    fail("the badge row has a reviewer badge, not a harness badge")
harness = [(s, a) for s, a in badges if a.startswith("harness:") and "/badge/harness-" in s]
if len(harness) != 1:
    fail("the badge row has %d harness badges (alt \"harness: ...\", label harness), not one" % len(harness))
s, a = harness[0]
named = [n.strip() for n in a.split(":", 1)[1].split("|")]
for cli in ("Claude Code", "Codex", "OpenCode"):
    if cli not in named:
        fail("the harness badge's alt text does not name %s: %s" % (cli, a))
    if cli not in s:
        fail("the harness badge's picture does not name %s: %s" % (cli, s))
EOF
