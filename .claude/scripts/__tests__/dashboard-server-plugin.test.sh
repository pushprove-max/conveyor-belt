#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# POST /plugin-dismiss (issue 1042): the Plugin problems pane's Dismiss removes one note from a Foreman's
# plugin-bugs.md and files nothing. Bugs each case catches: a Dismiss that removed more than that one line, or none;
# one that ran gh; a write to a file the Board did not read its notes from (any path a page could name); a write taken
# without a login or from another site's page.
# POST /plugin-preview and /plugin-file (issue 1043): File on GitHub. Bugs each case catches: a preview whose title is
# not the note's first clause, or whose body lacks the note, version, commit or system, or names the card's project;
# an issue filed in another repository than plugin.json names, or with other text than the owner's edits; a title or
# body with a home path or a private address that reached gh, or a refusal that did not name the hit; a failed gh call
# that removed the note; a filing that removed or filed the other note too; a note that names its issue filed again;
# a host file that does not read taken as no terms file.
# The server runs in this process, over plain HTTP: what is checked is the handler, not TLS. Its requests come from
# this device, which "No login on this device" (on with no value stored) lets in with no login.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out" "$T/auth" "$T/bin" "$T/fm"
# A gh that keeps each call's arguments and the --body-file it was given (gh_write's copy of the body) and answers the
# issue's URL in the --repo it was given, or fails while gh-fail is there.
# stub: it leaves a mark when run, so the case can show Dismiss never runs it, which the shared stub cannot show.
printf '#!/usr/bin/env bash\nT=%q\ntouch "$T/gh-ran"\n[ ! -e "$T/gh-fail" ] || { echo "HTTP 401: Bad credentials" >&2; exit 1; }\nprintf "%%s\\n" "$@" > "$T/gh-args"; echo call >> "$T/gh-calls"\nwhile [ $# -gt 0 ]; do [ "$1" != --repo ] || r=$2; [ "$1" != --body-file ] || cat -- "$2" > "$T/gh-body"; shift; done\necho "https://github.com/$r/issues/77"\n' "$T" > "$T/bin/gh"; chmod +x "$T/bin/gh"
# The Board files through conveyor.sh gh-write on its checkout (CONVEYOR_MAIN, here $T), which reads that checkout's pack.
mkdir -p "$T/.conveyor" && cp "$HERE/../../../.conveyor/project.json" "$T/.conveyor/"
PATH=$T/bin:$PATH CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl XDG_CONFIG_HOME=$T/config \
  HOME=$T CONVEYOR_MAIN=$T "$PY" -I - "$HERE/.." "$T" <<'EOF'
import fcntl, functools, http.client, io, json, os, re, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

T = sys.argv[2]
OUT, NOTES, OTHER = os.path.join(T, 'out'), os.path.join(T, 'fm', 'plugin-bugs.md'), os.path.join(T, 'fm', 'other.md')
HEAD = '# Plugin problems the Foreman noted (for the conveyor-belt repo)\n\n'
# As the Foreman notes one (foreman-session.test.sh): its finding and evidence path name the card, so its project.
A = ('- 2026-11-20T09:00:00Z · card c20261120T080000-sample-7 · setup never sets linkFromMain, so card c20261120T080000-sample-7'
     ' has no packages · evidence: ~/cards/c20261120T080000-sample-7/test.log')
B = '- 2026-11-20T09:10:00Z · card - · npm ci runs twice · evidence: -'
with open(NOTES, 'w') as f:
    f.write(HEAD + A + '\n' + B + '\n')
os.chmod(NOTES, 0o600)
with open(OTHER, 'w') as f:
    f.write(B + '\n')
# data.js as dashboard.sh writes it: the Health part names the one file the Board read notes from.
with open(os.path.join(OUT, 'data.js'), 'w') as f:
    f.write('window.DASH = %s;\n' % json.dumps({'panels': {'health': {'error': None, 'data': {'pluginBugs': [
        {'repo': 'sample', 'projects': ['sample'], 'count': 2, 'file': NOTES, 'url': 'plugin-bugs/sample.txt', 'notes': []}]}}}}))
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=OUT))
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()
passed = [0]


def check(case, ok, why=''):
    if not ok:
        sys.exit('FAIL: %s: %s' % (case, why))
    passed[0] += 1


def call(path, body, host='localhost:%d' % PORT, origin=None):
    c = http.client.HTTPConnection('127.0.0.1', PORT, timeout=30)
    c.request('POST', path, body=json.dumps(body).encode(),
              headers={'Host': host, 'Origin': origin or 'https://' + host, 'Content-Type': 'application/json'})
    r = c.getresponse()
    said = r.read().decode()
    c.close()
    return r.status, said


def post(body, host='localhost:%d' % PORT, origin=None):
    return call('/plugin-dismiss', body, host, origin)[0]


def text(p):
    with open(p) as f:
        return f.read()


# Refused, and the file stays: no login, another site's page, a file the Board did not read, another key, a line
# that is not a note, a note no longer in the file.
WHOLE = HEAD + A + '\n' + B + '\n'
check('not_logged_in', post({'file': NOTES, 'line': B}, host='192.0.2.1:%d' % PORT) == 401 and text(NOTES) == WHOLE, text(NOTES))
check('other_site', post({'file': NOTES, 'line': B}, origin='https://example.com') == 403 and text(NOTES) == WHOLE, text(NOTES))
check('unread_file', post({'file': OTHER, 'line': B}) == 409 and text(OTHER) == B + '\n', text(OTHER))
check('other_key', post({'file': NOTES, 'line': B, 'all': True}) == 400 and text(NOTES) == WHOLE, text(NOTES))
check('not_a_note', post({'file': NOTES, 'line': '# Plugin problems the Foreman noted (for the conveyor-belt repo)'}) == 400 and text(NOTES) == WHOLE, text(NOTES))
check('gone_note', post({'file': NOTES, 'line': B + ' and more'}) == 409 and text(NOTES) == WHOLE, text(NOTES))
err, sys.stderr = sys.stderr, io.StringIO()
got = post({'file': NOTES, 'line': B})
log, sys.stderr = sys.stderr.getvalue(), err
check('dismisses_that_note_alone', got == 200 and text(NOTES) == HEAD + A + '\n', (got, text(NOTES)))
check('names_its_user', 'dashboard: plugin problem dismissed by %s from 127.0.0.1' % ds.LOCAL in log, log)
check('keeps_the_mode', os.stat(NOTES).st_mode & 0o777 == 0o600, oct(os.stat(NOTES).st_mode))
check('no_temp_left', sorted(os.listdir(os.path.dirname(NOTES))) == ['noprice.lock', 'other.md', 'plugin-bugs.md'], os.listdir(os.path.dirname(NOTES)))
check('runs_no_gh', not os.path.exists(os.path.join(T, 'gh-ran')), 'gh was run')
# Bug (R83): the Dismiss rewrote the file from the copy it had read with no lock, so a price note serve appended
# between that read and the replace was lost for good (noprice-noted then stops any later note). Here serve's append,
# made as noprice() makes it (under noprice.lock beside the file), starts just before the Dismiss replaces the file.
# Without the lock the append is waited for to its end (no timing guess), so the replace always loses it; with the
# lock held the append cannot start, and it lands after the replace.
P = '- 2026-11-20T09:30:00Z · card - · No built-in price for gpt-new-9: the belt runs or offers this Codex model · evidence: -'


def noprice_append():
    with open(os.path.join(os.path.dirname(NOTES), 'noprice.lock'), 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with open(NOTES, 'a') as f:
            f.write(P + '\n')


real_replace, appender = os.replace, threading.Thread(target=noprice_append)


def replace_late(src, dst):
    if dst == NOTES and appender.ident is None:  # the first replace only
        with open(os.path.join(os.path.dirname(NOTES), 'noprice.lock'), 'a') as probe:
            try:
                fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
                held = False
            except BlockingIOError:
                held = True
        threading.Thread.start(appender)
        if not held:  # the Dismiss takes no lock: the append finishes before the replace, however slow it is
            appender.join(30)
    return real_replace(src, dst)


with open(NOTES, 'w') as f:
    f.write(WHOLE)
os.replace = replace_late
err, sys.stderr = sys.stderr, io.StringIO()
got = post({'file': NOTES, 'line': B})
sys.stderr = err
os.replace = real_replace
appender.join(10)
check('keeps_a_note_appended_meanwhile', got == 200 and text(NOTES) == HEAD + A + '\n' + P + '\n',
      'dismiss of %r with a noprice append before its replace: %s %r' % (B, got, text(NOTES)))

# #1462 (R13). Bug: two Dismisses at once, of two notes, each read the file, took its own note out of its copy and
# replaced the file with it: the second replace put back the note the first had taken out. The replace is gated by a
# barrier for two: two Dismisses that both read before either replaced pass it together; one that waits on the lock
# for the other reaches it alone, and replaces once the barrier gives up.
gate = threading.Barrier(2, timeout=0.5)


def replace_gated(src, dst):
    if dst == NOTES:
        try:
            gate.wait()
        except threading.BrokenBarrierError:
            pass
    return real_replace(src, dst)


with open(NOTES, 'w') as f:
    f.write(WHOLE)
both = {}
dismissers = [threading.Thread(target=lambda n: both.__setitem__(n, post({'file': NOTES, 'line': n})), args=(n,)) for n in (A, B)]
os.replace = replace_gated
err, sys.stderr = sys.stderr, io.StringIO()
list(map(threading.Thread.start, dismissers))
for t in dismissers:
    t.join(30)
sys.stderr = err
os.replace = real_replace
check('two_dismisses_at_once', both == {A: 200, B: 200} and text(NOTES) == HEAD,
      'dismiss of %r and of %r at once: %r %r' % (A, B, both, text(NOTES)))

# File on GitHub, with both notes in the file again.
with open(NOTES, 'w') as f:
    f.write(WHOLE)
with open(os.path.join(sys.argv[1], '..', '..', '.claude-plugin', 'plugin.json')) as f:
    PLUGIN = json.load(f)
REPO = PLUGIN['repository'].split('github.com/', 1)[1]
got, said = call('/plugin-preview', {'file': NOTES, 'line': A})
prev = json.loads(said) if got == 200 else {}
check('preview_title', prev.get('title') == 'setup never sets linkFromMain' and prev.get('repo') == REPO, (got, said))
check('preview_body', prev['body'].startswith('setup never sets linkFromMain, so card <card> has no packages\nEvidence: ~/cards/<card>/test.log\n\n')
      and 'Plugin version: %s\n' % PLUGIN['version'] in prev['body'] and re.search(r'Engine commit: [0-9a-f]{40}\n', prev['body'])
      and re.search(r'System: \S', prev['body']) and 'sample' not in prev['body'], prev['body'])
# Bug (#1350): a note written with an issue number as its card field had that number hidden as <card> in the body; an
# issue number names no project, so it stays, and a card id in the field is still <card>.
_, issue_body = ds.note_issue('- 2026-11-22T09:00:00Z · card #12 · the fix covers #12 and #13 · evidence: -')
check('issue_card_kept', 'the fix covers #12 and #13' in issue_body and '<card>' not in issue_body, issue_body)
_, id_body = ds.note_issue('- 2026-11-22T09:00:00Z · card c20261122T090000-sample-7 · see c20261122T090000-sample-7 · evidence: -')
check('card_id_hidden', id_body.startswith('see <card>\n\n') and 'sample' not in id_body, id_body)
# Bug caught: only the card field's id was hidden, so a note whose field is '-', or whose text compares a second card,
# gave that card's id, and with it the project's name, in the report. Every card id the note says is <card>; a file
# named for a card keeps its extension.
_, dash_body = ds.note_issue('- 2026-11-22T09:00:00Z · card - · compare card c20261118T045400-alpha-6, status shows the wrong count · evidence: -')
check('other_card_hidden_no_field', 'alpha' not in dash_body and dash_body.startswith('compare card <card>, status'), dash_body)
_, two_body = ds.note_issue('- 2026-11-22T09:00:00Z · card c20261118T045400-alpha-7 · compare card c20261118T045400-alpha-6 with ~/cards/c20261118T045400-alpha-7.err · evidence: ~/cards/c20261118T045400-alpha-7.err')
check('other_card_hidden', 'alpha' not in two_body and two_body.startswith('compare card <card> with ~/cards/<card>.err\n'), two_body)
# Bug caught: a card id that ends a sentence ('see <id>.') was not hidden, as the stop after it is a character a card id
# may hold: the project's name was in the title and the body. A project name with a '-' in it is hidden whole.
stop_title, stop_body = ds.note_issue('- 2026-11-22T09:00:00Z · card c20261122T090000-sample-7 · see c20261122T090000-sample-7. Then c20261122T090000-big-sample-8. · evidence: -')
check('card_id_stop_hidden', 'sample' not in stop_title + stop_body and stop_body.startswith('see <card>. Then <card>.\n'), (stop_title, stop_body))
# Bug (#1351): the body gave the evidence path twice, once in the note's text and again as ' · evidence: <path>'. The body
# has the path once: in the text when the text names it, else as its own line 'Evidence: <path>'.
_, named = ds.note_issue('- 2026-11-22T09:00:00Z · card - · setup fails, evidence ~/logs/setup.log (line 4) · evidence: ~/logs/setup.log')
check('evidence_named_once', named.count('~/logs/setup.log') == 1 and 'Evidence:' not in named, named)
# Bug (review of #1351): the title was cut from the text after the Evidence line was added, so it read 'setup fails\nEvidence'.
unnamed_title, unnamed = ds.note_issue('- 2026-11-22T09:00:00Z · card - · setup fails · evidence: ~/logs/setup.log')
check('evidence_title_clean', unnamed_title == 'setup fails', unnamed_title)
check('evidence_line_once', unnamed.startswith('setup fails\nEvidence: ~/logs/setup.log\n\n') and unnamed.count('Evidence: ~/logs/setup.log') == 1, unnamed)
# Bug (#1357): a guessed cause was part of the finding's text, so the report stated it as fact. The note's
# 'cause not checked:' part is its own body line 'Cause (not checked): <text>', once; a note without one has no such line.
cause_title, cause_body = ds.note_issue('- 2026-11-22T09:00:00Z · card - · setup fails, cause not checked: the cache, maybe, is stale, card c20261122T090000-sample-7, evidence ~/logs/setup.log · evidence: ~/logs/setup.log')
check('cause_line_once', cause_body.count('Cause (not checked): the cache, maybe, is stale\n') == 1 and cause_body.count('Cause (not checked)') == 1
      and cause_body.startswith('setup fails, card <card>, evidence ~/logs/setup.log\n') and cause_title == 'setup fails', (cause_title, cause_body))
# Bug (review of #1357): the cause ended at any ', card ' or ', evidence ', so words of the guess ('card lookups use old
# data') were left in the report's text as fact. Only a card id or an evidence path ends it.
_, words_body = ds.note_issue('- 2026-11-22T09:00:00Z · card - · setup fails, cause not checked: the cache is stale, card lookups use old data, evidence the log, card c20261122T090000-sample-7, evidence ~/logs/setup.log · evidence: ~/logs/setup.log')
check('cause_keeps_card_words', words_body.startswith('setup fails, card <card>, evidence ~/logs/setup.log\n')
      and words_body.count('Cause (not checked): the cache is stale, card lookups use old data, evidence the log\n') == 1, words_body)
# Bug (review of #1357): empty fields ('card -, evidence -') after the cause were part of it: the report's cause line read
# 'the cache is stale, card -, evidence -'. A '-' is a field's empty value and ends the cause like an id or a path.
_, empty_body = ds.note_issue('- 2026-11-22T09:00:00Z · card - · setup fails, cause not checked: the cache is stale, card -, evidence - · evidence: -')
check('cause_ends_at_empty_fields', empty_body.startswith('setup fails, card -, evidence -\nCause (not checked): the cache is stale\n'), empty_body)
# Bug (review of #1357): when the hook put the whole claim in the cause part (a [likely] tag at the end), only the card
# and evidence fields stayed outside it, and the title was 'card <card>'. The title is the cause's first clause.
whole_title, whole_body = ds.note_issue('- 2026-11-22T09:00:00Z · card c20261122T090000-sample-7 · cause not checked: running cards keep the old engine code, card c20261122T090000-sample-7, evidence ~/cards/x.err · evidence: ~/cards/x.err')
check('cause_only_title', whole_title == 'running cards keep the old engine code', (whole_title, whole_body))
# Bug (#1436): the guide said the title is the note's first clause, but a note made only of an unchecked cause takes its
# title from the cause's first clause (above), and the body has the cause as its own line 'Cause (not checked): <cause>'.
with open(os.path.join(sys.argv[1], '..', '..', 'docs', 'board.md'), encoding='utf-8') as f:
    GUIDE = re.sub(r'\s+', ' ', f.read().replace('**', ''))
check('cause_only_guide', '\nCause (not checked): ' + whole_title + '\n' in whole_body + '\n'
      and 'takes its title from the first clause of the cause' in GUIDE and 'as "Cause (not checked):"' in GUIDE, (GUIDE.find('takes its title'), whole_body))
check('no_cause_no_line', 'Cause' not in named and 'Cause' not in unnamed, (named, unnamed))
check('preview_writes_nothing', text(NOTES) == WHOLE and not os.path.exists(os.path.join(T, 'gh-ran')), text(NOTES))
# Built in parts, so this file holds no home path or private address itself.
HOMEPATH, PRIVATE = '/ho' + 'me/someone/notes.txt', '10.' + '1.2.3'
got, said = call('/plugin-file', {'file': NOTES, 'line': B, 'title': 'npm ci on ' + PRIVATE, 'body': 'first\nsee ' + HOMEPATH + '\n'})
check('privacy_refused', got == 422 and 'the title: private address' in said and 'body line 2: home path' in said
      and HOMEPATH not in said and PRIVATE not in said, (got, said))
check('privacy_before_gh', not os.path.exists(os.path.join(T, 'gh-ran')) and text(NOTES) == WHOLE, text(NOTES))
open(os.path.join(T, 'gh-fail'), 'w').close()
got, said = call('/plugin-file', {'file': NOTES, 'line': B, 'title': 'npm ci runs twice', 'body': 'b\n'})
check('gh_failed_keeps_note', got == 502 and 'HTTP 401: Bad credentials' in said and text(NOTES) == WHOLE, (got, said, text(NOTES)))
os.remove(os.path.join(T, 'gh-fail'))
os.remove(os.path.join(T, 'gh-ran'))
got, said = call('/plugin-file', {'file': NOTES, 'line': B, 'title': 'npm ci runs twice in setup', 'body': 'edited body\n'})
URL = 'https://github.com/%s/issues/77' % REPO
check('files_the_edits', got == 200 and said == URL, (got, said))
with open(os.path.join(T, 'gh-args')) as f:
    args = f.read().splitlines()
# Bug (#1064): the Board ran gh itself, outside the engine's privacy gate. gh_write hands gh the body as a file it
# keeps under <state>/privacy, never the Board's standard input.
check('gh_issue_create', args[:-1] == ['issue', 'create', '--repo', REPO, '--title', 'npm ci runs twice in setup', '--body-file']
      and args[-1].startswith(os.path.join(T, 'conveyor', 'state', 'privacy') + os.sep), args)
check('gh_body', text(os.path.join(T, 'gh-body')) == 'edited body\n', text(os.path.join(T, 'gh-body')))
check('removes_that_note_alone', text(NOTES) == HEAD + A + '\n', text(NOTES))
check('other_note_unfiled', text(os.path.join(T, 'gh-calls')) == 'call\n', text(os.path.join(T, 'gh-calls')))
# Bug (E2): a note the Foreman marked "filed as #<n>" could be previewed and filed again.
C = '- 2026-11-20T09:20:00Z · card - · running cards keep the old engine code, filed as #449 · evidence: -'
with open(NOTES, 'a') as f:
    f.write(C + '\n')
got_p, said_p = call('/plugin-preview', {'file': NOTES, 'line': C})
got_f, said_f = call('/plugin-file', {'file': NOTES, 'line': C, 'title': 'running cards keep the old engine code', 'body': 'c\n'})
check('filed_note_not_filed_again', got_p == 409 and got_f == 409 and 'filed as' in said_f
      and text(os.path.join(T, 'gh-calls')) == 'call\n' and text(NOTES) == HEAD + A + '\n' + C + '\n', (got_p, said_p, got_f, said_f))
# Bug (R28): a reply line ending ",filed as #449" (no space after the comma, which stop.sh accepts) left a note that
# the Board did not know as filed, so it could be previewed and filed again.
C2 = '- 2026-11-20T09:30:00Z · card - · running cards keep the old engine code,filed as #449 · evidence: -'
with open(NOTES, 'a') as f:
    f.write(C2 + '\n')
got_p2, said_p2 = call('/plugin-preview', {'file': NOTES, 'line': C2})
check('filed_note_without_space_not_previewed', got_p2 == 409, (got_p2, said_p2))
with open(NOTES, 'w') as f:
    f.write(HEAD + A + '\n' + C + '\n')
# Bug (E1): a host file that did not read was taken as no terms file, so a private name only its terms file lists
# could reach gh. It refuses the filing, as gh_write does.
os.makedirs(os.path.join(T, 'config', 'conveyor'))
with open(os.path.join(T, 'config', 'conveyor', 'host.json'), 'w') as f:
    f.write('{"terms": ')
got, said = call('/plugin-file', {'file': NOTES, 'line': A, 'title': 'setup never sets linkFromMain', 'body': 'a\n'})
check('unread_host_file_refused', got == 500 and 'the host file does not read' in said
      and text(os.path.join(T, 'gh-calls')) == 'call\n' and text(NOTES) == HEAD + A + '\n' + C + '\n', (got, said))
srv.shutdown()
print('PASS: dashboard-server-plugin (%d checks)' % passed[0])
EOF
