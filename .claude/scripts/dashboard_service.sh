#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# A part of dashboard.sh, sourced by it, never run: the user service (--install, --restart, --update, --uninstall)
# and the page server's certificate.

# The launchd label prefix of the Mac's job (host-services.sh's HS_PREFIX): --restart and --uninstall find the job by it.
LABEL_PREFIX=com.conveyor.

# The job runs BOARD's copy (the primary checkout's, or the release install's). Every file it points at is checked
# before anything changes.
install() {
  local script=$BOARD/scripts/$NAME.sh f
  for f in "$script" "$VIEW_SRC/index.html" "$VIEW_SRC/app.css" "$VIEW_SRC/app.js"; do
    [ -s "$f" ] || { echo "dashboard: install needs $f, which is missing or empty" >&2; return 1; }
  done
  bash -n "$script" || { echo "dashboard: $script does not parse" >&2; return 1; }
  mkdir -p "$OUT" || return 1
  copy_view || return 1
  # The server needs the Board's own packages; without them the restarted job would serve nothing.
  "$BOARD_PY" -c 'import pyotp, segno, cryptography' 2>/dev/null \
    || { echo "dashboard: the Board's Python ($BOARD_PY) or its packages are missing: run /conveyor-belt:setup (conveyor.sh doctor names what is missing)" >&2; return 1; }
  # The page is served over HTTPS only; this makes the self-signed certificate once and keeps it after that.
  "$BOARD_PY" "${script%/*}/dashboard_server.py" make-cert >/dev/null || { echo "dashboard: could not make the HTTPS certificate" >&2; return 1; }
  # A restart that no one can get past the login (No login on this device off, and no admin with a password) serves a
  # page nobody can open, and the old server is gone by then. Asked here with the environment the job below is given,
  # so the store checked is the store the restarted job serves.
  "$BOARD_PY" "${script%/*}/dashboard_server.py" can-open || return 1
  # Every override set at install time goes into the job; with only PATH and HOME it reads the default folders.
  local k mac="" sysd=""
  for k in CONVEYOR_DASHBOARD_AUTH CONVEYOR_RULING_LOG CONVEYOR_DASHBOARD_DIR CONVEYOR_MAIN CONVEYOR_WORKSPACES CONVEYOR_SCRATCH XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME; do
    [ -n "${!k:-}" ] || continue
    mac+="<key>$k</key><string>$(xml "${!k}")</string>"; sysd+="Environment=\"$k=${!k}\""$'\n'
  done
  if [ "$(host_os)" = Darwin ]; then
    local plist=$HOME/Library/LaunchAgents/$LABEL_PREFIX$NAME.plist
    mkdir -p "${plist%/*}" || return 1
    cat > "$plist.new.$$" <<EOF || { rm -f "$plist.new.$$"; return 1; }
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL_PREFIX$NAME</string>
<key>ProgramArguments</key><array><string>$(xml "$BASH")</string><string>$(xml "$script")</string><string>--loop</string></array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>$(xml "$PATH")</string><key>HOME</key><string>$(xml "$HOME")</string>$mac</dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>$(xml "$OUT/$NAME.log")</string>
<key>StandardErrorPath</key><string>$(xml "$OUT/$NAME.log")</string>
</dict></plist>
EOF
    mv -f "$plist.new.$$" "$plist" || return 1
    launchctl bootout "gui/$(id -u)/$LABEL_PREFIX$NAME" 2>/dev/null || true
    # bootout returns before the job is gone; bootstrapping in that window fails (error 5).
    for _ in $(seq 50); do launchctl print "gui/$(id -u)/$LABEL_PREFIX$NAME" >/dev/null 2>&1 || break; sleep 0.1; done
    launchctl bootstrap "gui/$(id -u)" "$plist" || { echo "dashboard: launchctl refused $plist" >&2; return 1; }
  else
    local svc=$HOME/.config/systemd/user/$NAME.service
    mkdir -p "${svc%/*}" || return 1
    cat > "$svc" <<EOF || return 1
[Unit]
Description=Conveyor dashboard: re-collects $OUT/data.js every 60 s

[Service]
ExecStart="$BASH" "$script" --loop
Environment="PATH=$PATH"
Environment="HOME=$HOME"
${sysd}Restart=always
RestartSec=10
MemoryMax=256M

[Install]
WantedBy=default.target
EOF
    # restart, not `enable --now`, which leaves a running service on its old service file.
    systemctl --user daemon-reload && systemctl --user enable "$NAME.service" && systemctl --user restart "$NAME.service"
  fi
}

# The job's own manager restarts it; the label is the one install wrote.
# cert -- the page server's certificate, kept when it loads, else made again by make-cert, with one line in the log
# that says why (make-cert's first line). 1 when openssl could not make it; the server's own error then follows.
cert() {
  local out
  out=$("$BOARD_PY" "$HERE/dashboard_server.py" make-cert 2>&1) \
    || { echo "$(date +%FT%T) dashboard: could not make the HTTPS certificate: ${out//$'\n'/ }" >&2; return 1; }
  [[ $out == 'certificate kept: '* ]] || echo "$(date +%FT%T) dashboard: ${out%%$'\n'*}" >&2
}

restart() {
  if [ "$(host_os)" = Darwin ]; then launchctl kickstart -k "gui/$(id -u)/$LABEL_PREFIX$NAME"
  else systemctl --user --no-block restart "$NAME.service"; fi
}

# The files the loop's long-lived processes run or read once: the loop and the parts it sources, the page server and
# the parts it runs, the live feed and what the live feed reads when it starts (its records and their host). Every
# other file is read afresh by each cycle or request, so a change to it needs no restart.
RESTART_FILES=(.claude/scripts/dashboard.sh .claude/scripts/dashboard_panels.sh .claude/scripts/dashboard_service.sh
  .claude/scripts/dashboard_server.py .claude/scripts/dashboard_server_base.py .claude/scripts/dashboard_server_control.py
  .claude/scripts/dashboard_server_auth.py .claude/scripts/dashboard_server_pages.py .claude/scripts/dashboard_server_handler.py
  .claude/scripts/dashboard_stream.py conveyor/host.json)
# update -- brings the main checkout forward to origin/main (fetched at most every FETCH_EVERY seconds: fetch_main),
# by a fast-forward only, and restarts the service
# when one of RESTART_FILES changed. A checkout on another branch, with a merge in progress or with commits
# origin/main does not have is left as it is; a fast-forward that would overwrite a changed file is git's to refuse,
# with autostash off, so a changed file is never merged into the new code.
# Each run writes $OUT/update.json, which the Health part carries: {checkedAt, head, error (why the checkout was not
# brought forward), moved (the last move, kept across runs, so the page says the restart was on new code; with
# restartFailed while its restart has not succeeded, which each run retries)}.
update() {
  local m=$PP_MAIN br out err='' moved from to n restart=false
  moved=$(jq -ce '.moved | objects' "$OUT/update.json" 2>/dev/null) || moved=null
  # A restart that failed is still owed, through any later move too.
  if [ "$(jq -r '.restartFailed == true' <<<"$moved")" = true ]; then restart=true; moved=$(jq -c 'del(.restartFailed)' <<<"$moved"); fi
  br=$(git -C "$m" symbolic-ref -q --short HEAD 2>/dev/null) || br=''
  if [ "$br" != main ]; then err="the checkout is on ${br:-a detached HEAD}, not main; it is left as it is"
  elif git -C "$m" rev-parse -q --verify MERGE_HEAD >/dev/null; then err="a merge is in progress in the checkout; it is left as it is"
  elif ! out=$(fetch_main "$m" 2>&1); then err="origin/main could not be fetched: $({ grep -m 1 '^fatal:' <<<"$out" || tail -n 1 <<<"$out"; } | cut -c1-200)"
  elif ! n=$(git -C "$m" rev-list --count origin/main..main 2>&1); then err="origin/main could not be compared: $(tail -n 1 <<<"$n" | cut -c1-200)"
  elif [ "$n" -gt 0 ]; then err="main has $n commit(s) that origin/main does not; it is left as it is"
  elif [ "$(git -C "$m" rev-list --count main..origin/main)" -gt 0 ]; then
    from=$(git -C "$m" rev-parse HEAD)
    if ! out=$(git -C "$m" merge -q --ff-only --no-autostash origin/main 2>&1); then
      err="git refused the fast-forward: $(tr '\n\t' '  ' <<<"$out" | tr -s ' ' | cut -c1-300)"
    else
      to=$(git -C "$m" rev-parse HEAD)
      [ -z "$(git -C "$m" diff --name-only "$from" "$to" -- "${RESTART_FILES[@]}")" ] || restart=true
      moved=$(jq -cn --arg f "${from:0:12}" --arg t "${to:0:12}" --arg at "$(iso "$(date +%s)")" --argjson r $restart '{from: $f, to: $t, at: $at, restart: $r}')
      echo "$(date +%FT%T) dashboard: brought main forward ${from:0:12}..${to:0:12}$([ $restart = false ] || echo '; restarting on the new code')" >&2
    fi
  fi
  write_update "$err" "$moved" || return 1
  [ $restart = true ] || return 0
  restart && return 0
  write_update "the checkout moved to new code, but the restart failed; the dashboard still runs the old code" "$(jq -c '.restartFailed = true' <<<"$moved")"
  return 1
}
# fetch_main <checkout> -- fetches origin main at most every FETCH_EVERY seconds: $CACHE/update-fetched holds the time
# of the last fetch that worked, and a run before it is that old uses what that fetch got. A failed fetch writes no
# stamp, so the next run tries again; a stamp from the future (a clock set back) is taken as old.
FETCH_EVERY=300
fetch_main() {
  local now at
  now=$(date +%s); at=$(cat "$CACHE/update-fetched" 2>/dev/null) || at=''
  [[ $at =~ ^[0-9]+$ ]] && [ "$at" -le "$now" ] && [ $((now - at)) -lt $FETCH_EVERY ] && return 0
  timeout 120 git -C "$1" fetch -q origin main || return 1
  mkdir -p "$CACHE" && echo "$now" > "$CACHE/update-fetched"
}
# write_update <error> <moved> -- update.json, written whole.
write_update() {
  jq -cn --arg at "$(iso "$(date +%s)")" --arg h "$(git -C "$PP_MAIN" rev-parse --short=12 HEAD 2>/dev/null)" --arg e "$1" --argjson mv "$2" \
    '{checkedAt: $at, head: (if $h == "" then null else $h end), error: (if $e == "" then null else $e end), moved: $mv}' > "$OUT/.update.json.$$" \
    && mv -f "$OUT/.update.json.$$" "$OUT/update.json"
}

uninstall() {
  if [ "$(host_os)" = Darwin ]; then
    launchctl bootout "gui/$(id -u)/$LABEL_PREFIX$NAME" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$LABEL_PREFIX$NAME.plist"
  else
    systemctl --user disable --now "$NAME.service" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$NAME.service"
    systemctl --user daemon-reload
  fi
}
