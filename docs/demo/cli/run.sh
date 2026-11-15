#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# run.sh -- runs as dev in record-cli.sh's container: sets up the invented project example/acme-api, the plugin
# installed in Claude Code, and a belt that answers from the demo's timeline (mock.js, with conveyor.sh in place of
# the engine's), then records cli.tape with VHS and cuts it into /out/beat9.mp4 and /out/foreman.mp4, each fitted to
# its section's length in index.html. The Claude login is the read-only folder at /login: only its
# .credentials.json is copied. No real repository, card or GitHub call is used: the project's origin is a local folder.
set -euo pipefail
P=$HOME/conveyor-belt
D=$P/docs/demo
# The pin the project's pack names: the version folder that holds the plugin with the demo's engine.
PIN=0000000000000000000000000000000000000000
V=$HOME/.local/share/conveyor/versions/$PIN
# The length of beat 10 (/units) as cli.tape shows it: the clip is cut there.
B9=9

# Claude Code: the login, signed in, its first-run screens done and the project trusted.
mkdir -p ~/.claude && cp /login/.credentials.json ~/.claude/.credentials.json && chmod 600 ~/.claude/.credentials.json
jq -n '{hasCompletedOnboarding: true, theme: "dark", projects: {"/home/dev/acme-api": {hasTrustDialogAccepted: true, hasCompletedProjectOnboarding: true}}}' > ~/.claude.json

git config --global user.name dev && git config --global user.email dev@users.noreply.github.com && git config --global init.defaultBranch main
# The invented project, with a local origin named as on GitHub, and its pack.
mkdir -p ~/example && git init -q --bare ~/example/acme-api.git && git clone -q ~/example/acme-api.git ~/acme-api 2>/dev/null
mkdir -p ~/acme-api/.conveyor && jq -n --arg p "$PIN" '{plugin: {commit: $p}, defaultBranch: "main", test: {command: "npm test"}}' > ~/acme-api/.conveyor/project.json
git -C ~/acme-api add -A && git -C ~/acme-api commit -qm "first commit" && git -C ~/acme-api push -q origin main

# The plugin's engine for the pin, with the demo's conveyor.sh in front of it, also on PATH.
mkdir -p "$(dirname "$V")" ~/bin && cp -a "$P" "$V"
mv "$V/conveyor/conveyor.sh" "$V/conveyor/engine.sh" && cp "$D/cli/conveyor.sh" "$V/conveyor/conveyor.sh"
ln -s "$V/conveyor/conveyor.sh" ~/bin/conveyor.sh
export PATH=$HOME/bin:$PATH

# The host file: this machine is the host (no ssh), with the one record. The Board job's unit names the live feed's
# folder, which /units reads.
mkdir -p ~/.config/conveyor ~/.config/systemd/user
printf '%s\n' 'Example Client Ltd' > ~/.config/conveyor/terms
jq -n --arg v "$V" '{terms: "~/.config/conveyor/terms", host: "acme", main: $v, records: [{repo: "acme-api", main: "/home/dev/acme-api"}]}' > ~/.config/conveyor/host.json
printf 'ExecStart="/bin/bash" "%s/.claude/scripts/dashboard.sh" --loop\nEnvironment="CONVEYOR_DASHBOARD_DIR=%s/.board"\n' "$V" "$HOME" > ~/.config/systemd/user/dashboard.service

# The Foreman: its watchers ask the demo's engine (lib.sh ask's seam), and its project's rules say how it clears a
# blocked card.
# shellcheck disable=SC2016 # lib.sh ask expands it, with CONVEYOR_CMD set
export CONVEYOR_FOREMAN_ASK='exec conveyor.sh $CONVEYOR_CMD'
FD=$(CONVEYOR_MAIN=$HOME/acme-api conveyor.sh state-dir)/foreman
mkdir -p "$FD" && cat > "$FD/rules.md" <<'EOF'
- A blocked card: ask the owner by the picker whether to retry it, with two options, "Retry #<issue>" first and
  "Leave it blocked". On "Retry #<issue>", run `conveyor.sh retry <issue>` and say in one line that the card is back
  on the belt.
EOF

# The plugin, installed from a marketplace folder on this machine.
mkdir -p ~/market/.claude-plugin && cp -a "$P" ~/market/conveyor-belt
jq -n '{name: "conveyor-belt", owner: {name: "dev"}, plugins: [{name: "conveyor-belt", source: "./conveyor-belt"}]}' > ~/market/.claude-plugin/marketplace.json
claude plugin marketplace add ~/market >/dev/null && claude plugin install conveyor-belt@conveyor-belt >/dev/null

node "$D/cli/mock.js" serve ~/.board 2 &
cd ~/acme-api
vhs "$D/cli/cli.tape"

# Each beat cut from the session and fitted to its section's length (data-duration of its video in index.html).
len() { sed -n "s|.*src=\"captures/$1.mp4\"[^>]*data-duration=\"\([0-9.]*\)\".*|\1|p" "$D/index.html"; }
total=$(ffprobe -v error -show_entries format=duration -of csv=p=0 /out/cli.mp4)
fit() { # <clip> <from s> <length s>
  ffmpeg -loglevel error -y -ss "$2" -t "$3" -i /out/cli.mp4 -an -vf "setpts=PTS*$(awk -v a="$(len "$1")" -v b="$3" 'BEGIN { print a / b }'),fps=30,format=yuv420p" \
    -c:v libx264 -crf 16 "/out/$1.mp4"
}
fit beat9 0 "$B9"
fit foreman "$B9" "$(awk -v t="$total" -v b="$B9" 'BEGIN { print t - b }')"
rm -f /out/cli.mp4
