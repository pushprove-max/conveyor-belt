#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# record-terminal.sh <out dir> -- the demo's beat 2: the install the README gives, as typed in Claude Code (the two
# /plugin lines, then /conveyor-belt:setup with its questions answered), run in a clean Docker container whose user,
# host and home are neutral (dev@acme, /home/dev), on an invented project (acme-api) with a local origin. Behind each
# line runs what it runs: claude's plugin commands, then conveyor.sh setup with the answers and conveyor.sh doctor, the
# output shown as printed. gh and claude are stand-ins, as in README.test.sh: gh answers as a signed-in account with
# the release and labels, claude records the plugin install. Writes <out dir>/beat2.txt (the session as typed and
# printed) and <out dir>/beat2.js (the same text for the composition: window.BEAT2 = "...").
# Exit 1 when Docker does not run, the container fails, or doctor names anything missing.
set -euo pipefail
OUT=${1:?usage: record-terminal.sh <out dir>}
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
IMAGE=conveyor-belt-demo-terminal
mkdir -p "$OUT"
docker info >/dev/null 2>&1 || { echo "record-terminal: Docker does not run on this machine" >&2; exit 1; }

# The image: the tools the README asks for, and the user dev with home /home/dev.
docker build -q -t "$IMAGE" - >/dev/null <<'EOF'
FROM ubuntu:24.04
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends bash jq git python3 python3-venv python3-pip util-linux ca-certificates >/dev/null \
  && rm -rf /var/lib/apt/lists/* && useradd -m -d /home/dev -s /bin/bash dev
USER dev
WORKDIR /home/dev
EOF

# The session the container runs: the stand-ins and the project first (not shown), then what is shown, each command
# after its prompt line.
read -r -d '' SESSION <<'EOS' || true
set -uo pipefail
export HOME=/home/dev GIT_CONFIG_NOSYSTEM=1
git config --global user.name dev && git config --global user.email dev@users.noreply.github.com && git config --global init.defaultBranch main
# The plugin's code, as the README clones it: the newest release, v1.0.0.
mkdir -p ~/src && tar -x -C ~/src
git -C ~/src init -q && git -C ~/src add -A && git -C ~/src commit -qm code && git -C ~/src tag v1.0.0 && git clone -q --bare ~/src ~/conveyor-belt.git
git clone -q --branch v1.0.0 ~/conveyor-belt.git ~/conveyor-belt 2>/dev/null
# The invented project, with an origin.
git init -q --bare ~/acme-api.git && git clone -q ~/acme-api.git ~/acme-api 2>/dev/null
git -C ~/acme-api commit -q --allow-empty -m "first commit" && git -C ~/acme-api push -q origin main && git -C ~/acme-api remote set-head origin -a >/dev/null
mkdir -p ~/bin ~/.config/conveyor && : > ~/.labels
cat > ~/bin/gh <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "label list") cat ~/.labels ;;
  "label create") [ "$3" = -- ] && echo "$4" >> ~/.labels ;;
  "auth status") exit 0 ;;
  "release view") echo v1.0.0 ;;
  "release list") echo '[{"tagName":"v1.0.0","isDraft":false,"isPrerelease":false}]' ;;
  *) exit 1 ;;
esac
GH
cat > ~/bin/claude <<'CL'
#!/usr/bin/env bash
[ "$1 $2 $3" = "plugin marketplace add" ] && { echo "Successfully added marketplace: ${4#*/}"; exit 0; }
[ "$1 $2" = "plugin install" ] || exit 0
f=~/.claude/plugins/installed_plugins.json; mkdir -p ~/.claude/plugins; [ -s "$f" ] || echo '{"version": 2, "plugins": {}}' > "$f"
jq --arg p "$3" '.plugins[$p] = [{scope: "user"}]' "$f" > "$f.new" && mv "$f.new" "$f"
echo "Successfully installed plugin: $3 (scope: user)"
CL
# conveyor.sh on PATH by its own name, so the screen's command lines are short.
printf '#!/bin/sh\n' > ~/bin/codex; chmod +x ~/bin/*; export PATH=~/bin:~/conveyor-belt/conveyor:$PATH
claude plugin install mattpocock-skills@claude-plugins-official >/dev/null
printf '%s\n' 'Example Client Ltd' > ~/.config/conveyor/terms
printf '{"terms": "~/.config/conveyor/terms", "host": "acme", "ssh": "localhost", "main": "%s/conveyor-belt", "records": [{"repo": "acme-api", "main": "%s/acme-api"}]}\n' "$HOME" "$HOME" > ~/.config/conveyor/host.json
cd ~/acme-api
# typed <line>: a line typed at Claude Code's prompt. asked <question> <answer>: a question setup asks, answered.
typed() { printf '> %s\n' "$1"; sleep 0.2; }
asked() { printf '? %s  %s\n' "$1" "$2"; }
{
  typed '/plugin marketplace add pushprove-max/conveyor-belt'; claude plugin marketplace add pushprove-max/conveyor-belt
  typed '/plugin install conveyor-belt@conveyor-belt'; claude plugin install conveyor-belt@conveyor-belt
  typed '/conveyor-belt:setup'
  asked 'Who approves a change that users will see?' 'Dev'
  asked 'Where is the product code?' 'src/'
  asked 'The command that runs the tests?' 'npm test'
  asked 'Run a first test-speed survey now?' 'no'
  conveyor.sh setup --owner "Dev" --product src/ --test "npm test" --survey no
  conveyor.sh doctor
} > ~/session.txt 2>&1
cat ~/session.txt
EOS

# The plugin's tracked files go in on standard input.
tracked() { git -C "$ROOT" ls-files -z | xargs -0 tar -c -C "$ROOT" --no-recursion 2>/dev/null; }
# The home is shown as ~, as the prompt shows it: the privacy check that make.sh runs on the frames refuses any home
# path, /home/dev too.
tracked | docker run --rm -i --hostname acme "$IMAGE" bash -c "$SESSION" | sed 's|/home/dev|~|g' > "$OUT/beat2.txt"

# The screen's text must be neutral: no home path left.
if grep -nE '/(Users|home)/' "$OUT/beat2.txt"; then echo "record-terminal: the session names a home path" >&2; exit 1; fi
grep -q '^missing' "$OUT/beat2.txt" && { echo "record-terminal: doctor names something missing:" >&2; grep '^missing' "$OUT/beat2.txt" >&2; exit 1; }
grep -q '^ok:' "$OUT/beat2.txt" || { echo "record-terminal: doctor printed no ok line" >&2; exit 1; }
printf 'window.BEAT2 = %s;\n' "$(jq -Rs . < "$OUT/beat2.txt")" > "$OUT/beat2.js"
