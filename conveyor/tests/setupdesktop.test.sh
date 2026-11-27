#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: `conveyor.sh setup desktop` (desktopbundle(), lib/setup.sh): /units for Claude Desktop's Chat tab as
# the bundle conveyor-units.mcpb in the state folder's desktop/, opened on macOS, its path printed elsewhere.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A bundle Desktop can install: a zip holding manifest.json, server.py and view.html, whose manifest names a python
# server with server.py as its entry and the project's main checkout as its one user config value. Fails with the
# bundle's file list and manifest when it is not one.
desktopcheck() { # <the command's output>
  local b=$ST/desktop/conveyor-units.mcpb names m
  names=$(python3 -I -c 'import sys, zipfile; print(" ".join(sorted(zipfile.ZipFile(sys.argv[1]).namelist())))' "$b" 2>&1) \
    && [ "$names" = 'manifest.json server.py view.html' ] || fail "setup desktop did not build a zip of manifest.json, server.py and view.html at $b: $names; its output: $1"
  m=$(python3 -I -c 'import sys, zipfile; print(zipfile.ZipFile(sys.argv[1]).read("manifest.json").decode())' "$b")
  jq -e --arg r "$R" '.server.type == "python" and .server.entry_point == "server.py" and (.user_config | keys) == ["checkout"]
    and .user_config.checkout.default == $r and (.server.mcp_config.args | index("${user_config.checkout}") != null)' <<<"$m" >/dev/null \
    || fail "setup desktop's manifest does not parse, or is not a python server.py with the checkout $R as its one user config value: $m"
}

# Bugs: on macOS the bundle was not built, held the wrong files, had a manifest Desktop cannot read or that points the
# server at another checkout, or was not handed to `open`, so Desktop never asked to install it.
t_setupdesktopmac() {
  setup '[]'; local mac=$T/$CASE/mac b=$T/$CASE/brew out k
  # macOS faked on Linux, as servicerenew.test.sh does: uname says Darwin and Homebrew's GNU tools are there, so
  # p_tools passes; `open` records what it was given.
  mkdir -p "$mac" "$b/bin" && printf '#!/bin/sh\necho Darwin\n' > "$mac/uname" && ln -s "$(command -v timeout)" "$b/bin/gtimeout" \
    && printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$T/$CASE/opened" > "$mac/open" && chmod +x "$mac/uname" "$mac/open" || fail "the macOS stubs were not made"
  for k in coreutils:timeout coreutils:date coreutils:stat findutils:find gnu-sed:sed grep:grep; do
    mkdir -p "$b/opt/${k%%:*}/libexec/gnubin" && ln -s "$(command -v "${k#*:}")" "$b/opt/${k%%:*}/libexec/gnubin/${k#*:}" || fail "the GNU tools were not linked"
  done
  out=$(cd "$R" && PATH=$mac:$b/bin:$PATH loop setup desktop 2>&1) || fail "setup desktop on macOS exited non-zero: $out"
  desktopcheck "$out"
  [ "$(cat "$T/$CASE/opened" 2>&1)" = "$ST/desktop/conveyor-units.mcpb" ] || fail "setup desktop on macOS did not open the bundle $ST/desktop/conveyor-units.mcpb once: open got $(cat "$T/$CASE/opened" 2>&1); its output: $out"
}

# Bugs: off macOS the bundle was not built, or its path was not printed (there is no `open` to hand it to), or a
# Linux `open` (run-mailcap's) was called.
t_setupdesktoplinux() {
  [ "$(uname -s)" = Linux ] || return 0
  setup '[]'; local out
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$T/$CASE/opened" > "$STUB/open" && chmod +x "$STUB/open" || fail "the open stub was not made"
  out=$(cd "$R" && loop setup desktop 2>&1) || fail "setup desktop on Linux exited non-zero: $out"
  desktopcheck "$out"
  grep -qF "$ST/desktop/conveyor-units.mcpb" <<<"$out" || fail "setup desktop on Linux did not print the bundle's path: $out"
  [ ! -e "$T/$CASE/opened" ] || fail "setup desktop on Linux called open: $(cat "$T/$CASE/opened")"
}
