#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The README's "How it works" diagram, docs/how-it-works.svg, as GitHub shows it: inside an <img>, where a script is
# stripped and only SMIL animates, for readers who may have asked for reduced motion.
# Bugs: a script or an on* handler in the file; no SMIL animation; an animation a prefers-reduced-motion reader still
# sees moving (each animation must sit in a group the reduced-motion rule hides, and a static frame takes its place).
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
python3 -I - "$SRC/how-it-works.svg" <<'EOF' && echo "ok how-it-works"
import re, sys
import xml.etree.ElementTree as ET

def fail(why):
    print("FAIL [how-it-works]: " + why, file=sys.stderr)
    sys.exit(1)

path = sys.argv[1]
try:
    root = ET.parse(path).getroot()
except (OSError, ET.ParseError) as e:
    fail("the diagram cannot be read as XML: %s" % e)
NS = "{http://www.w3.org/2000/svg}"
tag = lambda el: el.tag[len(NS):] if el.tag.startswith(NS) else el.tag
everything = list(root.iter())

if any(tag(el) in ("script", "foreignObject") for el in everything):
    fail("the diagram holds a script or a foreignObject")
for el in everything:
    for name, value in el.attrib.items():
        if name.lower().startswith("on") or "javascript:" in value.lower():
            fail("the diagram holds a script handler: %s on <%s>" % (name, tag(el)))

SMIL = ("animate", "animateMotion", "animateTransform", "set")
anims = [el for el in everything if tag(el) in SMIL]
if not anims:
    fail("the diagram does not animate with SMIL")

css = "".join(st.text or "" for st in root.iter(NS + "style"))
m = re.search(r"@media\s*\(\s*prefers-reduced-motion\s*:\s*reduce\s*\)\s*\{(.*?\})\s*\}", css, re.S)
if not m:
    fail("the diagram holds no prefers-reduced-motion rule")
hidden = set(re.findall(r"\.([\w-]+)\s*\{[^}]*display\s*:\s*none", m.group(1)))
shown = set(re.findall(r"\.([\w-]+)\s*\{[^}]*display\s*:\s*inline", m.group(1)))
if not hidden:
    fail("the reduced-motion rule hides nothing, so the animation keeps moving")

parent = {child: el for el in everything for child in el}
def classes_up(el):
    out = set()
    while el is not None:
        out |= set(el.get("class", "").split())
        el = parent.get(el)
    return out
for a in anims:
    if not classes_up(a) & hidden:
        fail("an <%s> is outside every group the reduced-motion rule hides" % tag(a))

# The static frame: shown only under reduced motion, and it holds no animation of its own.
still = [el for el in everything if set(el.get("class", "").split()) & shown]
if not still:
    fail("the reduced-motion rule shows no static frame in place of the animation")
for g in still:
    if any(tag(el) in SMIL for el in g.iter()):
        fail("the static frame shown under reduced motion animates")
EOF
