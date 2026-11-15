#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# record-cli.sh with a stub claude (CONVEYOR_DEMO_CLAUDE) and a stub docker on PATH, which notes each call and, for
# `run`, writes the clips into the folder mounted at /out as the container's cli/run.sh does. record-cli.sh runs from a
# copy in a git checkout of its own, so the checkout's captures folder is never written.
set -u
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/demo-record-cli-test.XXXXXX")
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

mkdir -p "$T/bin" "$T/login" "$T/nologin"
echo '{}' > "$T/login/.credentials.json"
printf '#!/bin/sh\necho "stub claude"\n' > "$T/claude"
cat > "$T/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB/docker.log"
case $1 in
  build) ctx=${*: -1}; cp "$ctx/Dockerfile" "$STUB/Dockerfile"; cp "$ctx/claude" "$STUB/claude.in" 2>/dev/null
    [ -f "$ctx/plugin/docs/demo/cli/run.sh" ] && touch "$STUB/run.in" ;;
  run) for a; do case $a in *:/out) out=${a%:/out} ;; esac; done
    for c in ${STUB_CLIPS-beat9 foreman}; do echo "$c clip" > "$out/$c.mp4"; done ;;
esac
EOF
chmod +x "$T/bin/docker"
# checkout <name>: a git checkout holding record-cli.sh and the container's script, as the plugin's does.
checkout() {
  mkdir -p "$T/$1/docs/demo/cli" && cp "$SRC/record-cli.sh" "$T/$1/docs/demo/" && cp "$SRC/cli/run.sh" "$T/$1/docs/demo/cli/"
  git -C "$T/$1" init -q && git -C "$T/$1" add -A
  mkdir -p "$T/$1.stub"
}
run() { # <checkout> <login folder> [<env>...]: record-cli.sh's output and exit code in $out and $rc
  local c=$1 l=$2; shift 2
  out=$(env "$@" STUB="$T/$c.stub" CONVEYOR_DEMO_CLAUDE="$T/claude" PATH="$T/bin:$PATH" bash "$T/$c/docs/demo/record-cli.sh" "$l" 2>&1); rc=$?
}

# Bug caught: the container runs as another user, host or home (the clips would show them), the login folder is
# mounted writable or not at all, the stand-in claude or the session's script is not in the image, or the clips the
# session wrote are not put in captures/ for make.sh.
checkout a; run a "$T/login"
[ "$rc" = 0 ] || fail "record-cli.sh exited $rc: $out"
r=$(grep '^run ' "$T/a.stub/docker.log")
for want in '--user dev' '--hostname acme' '-e HOME=/home/dev' "-v $T/login:/login:ro" 'bash /home/dev/conveyor-belt/docs/demo/cli/run.sh'; do
  grep -qF -- " $want" <<<" $r" || fail "docker run lacks '$want': $r"
done
grep -qE 'useradd .*-d /home/dev .*dev$' "$T/a.stub/Dockerfile" || fail "the image has no user dev with home /home/dev: $(cat "$T/a.stub/Dockerfile")"
if ! grep -qxF 'COPY --chmod=755 claude /usr/local/bin/claude' "$T/a.stub/Dockerfile" || ! cmp -s "$T/claude" "$T/a.stub/claude.in"; then
  fail "the image does not take the stub claude"
fi
[ -f "$T/a.stub/run.in" ] || fail "the image has no cli/run.sh"
for c in beat9 foreman; do
  [ "$(cat "$T/a/docs/demo/captures/$c.mp4" 2>/dev/null)" = "$c clip" ] || fail "captures/$c.mp4 was not written"
done

# Bug caught: a session that wrote only one clip passes, and make.sh later cuts a demo with an old or no foreman.mp4.
checkout b; run b "$T/login" STUB_CLIPS=beat9
if [ "$rc" != 1 ] || ! grep -qF 'wrote no foreman.mp4' <<<"$out"; then fail "a session with no foreman.mp4 did not fail naming it ($rc): $out"; fi
[ ! -e "$T/b/docs/demo/captures/beat9.mp4" ] || fail "a failed session still wrote captures/beat9.mp4"

# Bug caught: a folder with no login starts the container, which then records Claude Code asking to sign in.
checkout c; run c "$T/nologin"
if [ "$rc" != 1 ] || ! grep -qF 'no Claude login folder' <<<"$out"; then fail "a folder with no login was taken ($rc): $out"; fi
! grep -q '^run ' "$T/c.stub/docker.log" 2>/dev/null || fail "a folder with no login started the container"

[ "$fails" = 0 ] && echo "record-cli.test.sh: ok"
[ "$fails" = 0 ]
