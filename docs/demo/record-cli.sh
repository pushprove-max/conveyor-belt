#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# record-cli.sh <Claude login folder> -- the demo's beats 10 (/units beside the chat) and 11 (the Foreman), recorded
# from a real Claude Code session with the plugin installed, in a Docker container whose user, host and home are
# neutral (dev, acme, /home/dev), on the invented project example/acme-api. VHS drives the session from a script
# (cli/cli.tape) and records it; cli/run.sh sets the container up. What the session shows is the demo's timeline
# (timeline.js, by cli/mock.js): /units reads it as the Board's live feed, and the Foreman's watchers and its retry
# ask it through cli/conveyor.sh. No real repository, card or GitHub call is used.
# The login folder is a Claude Code config folder signed in on Linux (it holds .credentials.json); it is mounted
# read-only. Writes captures/beat9.mp4 and captures/foreman.mp4 beside this script, which make.sh cuts in.
# Exit 1 when Docker does not run, the folder holds no login, or the container does not write both clips.
# CONVEYOR_DEMO_CLAUDE (the tests' seam): a file the image takes as its claude, in place of the npm package.
set -euo pipefail
[ $# = 1 ] || { echo "usage: record-cli.sh <Claude login folder>" >&2; exit 2; }
LOGIN=$(cd "$1" 2>/dev/null && pwd -P) && [ -f "$LOGIN/.credentials.json" ] \
  || { echo "record-cli: $1 is no Claude login folder: it holds no .credentials.json" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/../.." && pwd -P)
IMAGE=conveyor-belt-demo-cli
docker info >/dev/null 2>&1 || { echo "record-cli: Docker does not run on this machine" >&2; exit 1; }

B=$(mktemp -d "${TMPDIR:-/tmp}/conveyor-demo-cli.XXXXXX")
trap 'rm -rf "$B"' EXIT
# The image: VHS (with its ffmpeg), node, Claude Code, the engine's tools, the plugin's tracked files and the user
# dev, with this user's id so the clips it writes are this user's.
mkdir -p "$B/ctx/plugin" "$B/out"
git -C "$ROOT" ls-files -z | (cd "$ROOT" && xargs -0 tar -c --no-recursion) | tar -x -C "$B/ctx/plugin"
if [ -n "${CONVEYOR_DEMO_CLAUDE:-}" ]; then
  cp "$CONVEYOR_DEMO_CLAUDE" "$B/ctx/claude" && install='COPY --chmod=755 claude /usr/local/bin/claude'
else
  install='RUN npm install -g --no-audit --no-fund @anthropic-ai/claude-code'
fi
cat > "$B/ctx/Dockerfile" <<EOF
FROM ghcr.io/charmbracelet/vhs:v0.10.0
ARG UID=1000
RUN sed -i -E "s/\\\\bstable/bookworm/g" /etc/apt/sources.list.d/*.sources && apt-get update -qq && apt-get install -y -qq --no-install-recommends bash jq git python3 util-linux ca-certificates nodejs npm >/dev/null \\
  && rm -rf /var/lib/apt/lists/* && useradd -o -m -d /home/dev -s /bin/bash -u "\$UID" dev
$install
COPY --chown=dev plugin /home/dev/conveyor-belt
ENV VHS_NO_SANDBOX=true
USER dev
WORKDIR /home/dev
ENTRYPOINT []
EOF
docker build -q --build-arg "UID=$(id -u)" -t "$IMAGE" "$B/ctx" >/dev/null

docker run --rm --user dev --hostname acme -e HOME=/home/dev -v "$LOGIN:/login:ro" -v "$B/out:/out" "$IMAGE" \
  bash /home/dev/conveyor-belt/docs/demo/cli/run.sh
for clip in beat9 foreman; do
  [ -s "$B/out/$clip.mp4" ] || { echo "record-cli: the session wrote no $clip.mp4" >&2; exit 1; }
done
mkdir -p "$HERE/captures"
cp "$B/out/beat9.mp4" "$B/out/foreman.mp4" "$HERE/captures/"
echo "record-cli: wrote captures/beat9.mp4 and captures/foreman.mp4"
