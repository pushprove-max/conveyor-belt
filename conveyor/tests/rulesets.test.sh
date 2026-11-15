#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: tools/rulesets.sh, which applies the repository's rulesets (.github/rulesets/) through the GitHub API.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs caught: once public, anyone with push access can move or delete a release tag, make a v* tag by hand, or
# force-push or delete main; or the rulesets block the engine's plain pushes to main, or block the admin's tag push
# from `conveyor.sh release` (no GitHub Actions runs to make one), or let that bypass move or delete a tag; or a
# re-run makes a second copy of a ruleset the repository has.
# A gh stub answers the rulesets list with one ruleset of main.json's name (id 7) and records each call with its body.
t_rulesets() {
  local d=$T/$CASE out rc b name main='' fixed='' create=''
  mkdir -p "$d/bin"; name=$(jq -r .name "$SRC/../.github/rulesets/main.json")
  jq -n --arg n "$name" '[{id: 7, name: $n}, {id: 9, name: "another"}]' > "$d/list.json"
  cat > "$d/bin/gh" <<EOF
#!/usr/bin/env bash
n=\$(( \$(ls "$d" | grep -c '^call\.') + 1 )); printf '%s\n' "\$*" > "$d/call.\$n"
prev=''; for a; do [ "\$prev" = --input ] && cp "\$a" "$d/body.\$n"; prev=\$a; done
case "\$*" in *--method*) echo '{"id": 40}' ;; *) cat "$d/list.json" ;; esac
EOF
  chmod +x "$d/bin/gh"
  out=$(PATH=$d/bin:$PATH "$SRC/tools/rulesets.sh" apply 2>&1); rc=$?
  [ $rc = 0 ] || fail "rulesets.sh apply exited $rc: $out"
  [ "$(cat "$d/call.1")" = "api --paginate repos/{owner}/{repo}/rulesets?includes_parents=false" ] || fail "the first call does not list the rulesets: $(cat "$d/call.1")"
  local calls=("$d"/call.*)
  [ "${#calls[@]}" = 4 ] || fail "not one list and three writes: $(cat "$d"/call.*)"
  for b in "$d"/body.*; do
    case $(jq -r .name "$b") in
      "$name") main=$b ;; *update*) fixed=$b ;; *release*) create=$b ;;
    esac
  done
  [ -n "$main" ] && [ -n "$fixed" ] && [ -n "$create" ] \
    || fail "the three rulesets were not all sent: $(cat "$d"/body.*)"

  # main: updated in place (PUT to its id), blocking force push and deletion, not plain pushes, with no bypass.
  grep -qx "api --method PUT repos/{owner}/{repo}/rulesets/7 --input .*/main.json" "$d/call.${main##*.}" \
    || fail "the main ruleset the repository has is not updated in place: $(cat "$d/call.${main##*.}")"
  jq -e '.target == "branch" and .enforcement == "active" and .conditions.ref_name.include == ["refs/heads/main"]
    and ([.rules[].type] | sort) == ["deletion", "non_fast_forward"] and .bypass_actors == []' "$main" > /dev/null \
    || fail "the main ruleset does not block exactly force push and deletion on main for everyone: $(cat "$main")"

  # v* tags: made new (POST); update and deletion blocked for everyone, creation for all but the admin role.
  grep -qx "api --method POST repos/{owner}/{repo}/rulesets --input .*/tags-fixed.json" "$d/call.${fixed##*.}" \
    && grep -qx "api --method POST repos/{owner}/{repo}/rulesets --input .*/tags-create.json" "$d/call.${create##*.}" \
    || fail "the tag rulesets the repository lacks are not made: $(cat "$d"/call.*)"
  jq -e '.target == "tag" and .enforcement == "active" and .conditions.ref_name.include == ["refs/tags/v*"]
    and ([.rules[].type] | sort) == ["deletion", "update"] and .bypass_actors == []' "$fixed" > /dev/null \
    || fail "the tag ruleset does not block update and deletion of v* tags for everyone: $(cat "$fixed")"
  jq -e '.target == "tag" and .enforcement == "active" and .conditions.ref_name.include == ["refs/tags/v*"]
    and [.rules[].type] == ["creation"]
    and .bypass_actors == [{actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "always"}]' "$create" > /dev/null \
    || fail "v* tag creation is not blocked for all but the repository admin role: $(cat "$create")"
  grep -qx "updated $name (id 40)" <<<"$out" && [ "$(grep -c '^made ' <<<"$out")" = 2 ] \
    || fail "the report does not name each ruleset and what was done: $out"
}

# Bug caught: a failed API call is reported as applied. The list call fails: exit 2 with gh's error, no write sent.
t_rulesetsfail() {
  local d=$T/$CASE out rc; mkdir -p "$d/bin"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/calls"\necho "HTTP 403: Resource not accessible" >&2; exit 1\n' "$d" > "$d/bin/gh"
  chmod +x "$d/bin/gh"
  out=$(PATH=$d/bin:$PATH "$SRC/tools/rulesets.sh" apply 2>&1); rc=$?
  [ $rc = 2 ] || fail "rulesets.sh exited $rc, not 2, when the list call failed: $out"
  grep -q 'HTTP 403' <<<"$out" || fail "gh's error is not shown: $out"
  [ "$(wc -l < "$d/calls")" = 1 ] || fail "calls were made after the list failed: $(cat "$d/calls")"
}
