# SPDX-License-Identifier: Apache-2.0
"""The fast resolver's text work (fastfit(), lib/claim.sh): the conflicts of a three-way merge as one numbered list for
the judge, and the judge's answer written back in their place.

  fastfit.py prompt <folder of the merged files> <list of the files, one a line>
  fastfit.py apply <worktree> <folder of the merged files> <list of the files> <the judge's answer>

A conflict runs from a `<<<<<<<` line to its `>>>>>>>` line. apply fails, writing nothing, when the answer holds no
JSON object, when it does not give each conflict a text, or when a text still holds a conflict marker.
"""
import json
import os
import re
import sys

CONTEXT = 3
MARK = re.compile(r"^(<{7}|\|{7}|={7}|>{7})( |$)")


def blocks(lines):
    """The conflicts of a file: (start, end) line indexes, end the `>>>>>>>` line's."""
    out, start = [], None
    for i, line in enumerate(lines):
        if line.startswith("<<<<<<<") and start is None:
            start = i
        elif line.startswith(">>>>>>>") and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        raise ValueError("a conflict that does not end")
    return out


def files(folder, listing):
    with open(listing, encoding="utf-8") as f:
        names = [n for n in f.read().split("\n") if n]
    for name in names:
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            yield name, f.read().split("\n")


def prompt(folder, listing):
    n = 0
    parts = []
    for name, lines in files(folder, listing):
        for start, end in blocks(lines):
            n += 1
            lo, hi = max(0, start - CONTEXT), min(len(lines), end + 1 + CONTEXT)
            parts.append("\n".join([f"### Conflict {n}: {name}, line {start + 1}",
                                    "Before it:", "```", *lines[lo:start], "```",
                                    "The conflict:", "```", *lines[start:end + 1], "```",
                                    "After it:", "```", *lines[end + 1:hi], "```"]))
    if n == 0:
        raise ValueError("no conflict found")
    print(f"{n} conflicts.\n\n" + "\n\n".join(parts))


def answer(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    a, b = text.find("{"), text.rfind("}")
    if a < 0 or b < a:
        raise ValueError("the answer holds no JSON object")
    got = json.loads(text[a:b + 1])
    if not isinstance(got, dict):
        raise ValueError("the answer is not a JSON object")
    return got


def apply(worktree, folder, listing, path):
    got = answer(path)
    n = 0
    done = []
    for name, lines in files(folder, listing):
        out, last = [], 0
        for start, end in blocks(lines):
            n += 1
            text = got.get(str(n))
            if not isinstance(text, str):
                raise ValueError(f"the answer gives conflict {n} no text")
            new = text.split("\n") if text != "" else []
            if new and new[-1] == "":
                new = new[:-1]
            if any(MARK.match(line) for line in new):
                raise ValueError(f"the answer for conflict {n} still holds a conflict marker")
            out += lines[last:start] + new
            last = end + 1
        out += lines[last:]
        done.append((name, out))
    if len(got) != n:
        raise ValueError(f"the answer gives {len(got)} texts for {n} conflicts")
    for name, out in done:
        with open(os.path.join(worktree, name), "w", encoding="utf-8") as f:
            f.write("\n".join(out))


def main(argv):
    try:
        if len(argv) == 3 and argv[0] == "prompt":
            prompt(argv[1], argv[2])
        elif len(argv) == 5 and argv[0] == "apply":
            apply(*argv[1:])
        else:
            print("usage: fastfit.py prompt <folder> <list> | apply <worktree> <folder> <list> <answer>", file=sys.stderr)
            return 2
    except (OSError, ValueError, UnicodeDecodeError) as e:
        print(f"fastfit: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
