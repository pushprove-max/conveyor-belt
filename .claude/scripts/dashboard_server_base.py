# SPDX-License-Identifier: Apache-2.0
# A part of dashboard_server.py, run in its namespace (run_part()), not a module of its own: the limits of what a
# request sends, the login's settings, the checks of a benchmark's arguments, the live feed, the compressed files and
# the kept history.
import re  # already in the namespace run_part() gives; named here so ruff finds the name the patterns below use

# An answer is {id, answer, askedAt, repo}, each checked before decision.sh sees it; repo is the host file's record
# whose ledger holds the decision.
MAX_ANSWER_BODY = 4096
MAX_TIME_BODY = 64     # POST /time: {"time": "24-hour"}
MAX_DISMISS_BODY = 16384  # POST /plugin-dismiss and /plugin-preview: {file, line}, one note of plugin-bugs.md
MAX_FILE_BODY = 65536  # POST /plugin-file: {file, line, title, body}, the note and the issue the owner edited
GH_LIMIT = 90          # POST /plugin-file: its one conveyor.sh gh-write, whose gh call gh_write stops at 60 s (lib/issues.sh)
RESTART_COOLDOWN = 60  # seconds between restarts; the stamp is a file because the restart kills this server
HISTORY_TTL = 60       # GET /history with no live feed gives the kept copy while it is this young (dashboard.sh's HISTORY_TTL)
STREAM_FRESH = 60      # stream.json older than this: no live feed, so no ledger key (dashboard_panels.sh's STREAM_FRESH)
HISTORY_LIMIT = 90    # GET /history: dashboard.sh --history's one ssh command (its SSH_LIMIT, 60 s) and the build
WORK_LIMIT = 90        # GET /work: dashboard.sh --work's one ssh command (its SSH_LIMIT, 60 s) and the merge
OLDER_LIMIT = 90       # GET /older: dashboard.sh --older's one ssh command (its SSH_LIMIT, 60 s) and the tagging
DONEWHEN_LIMIT = 90    # GET /donewhen and /excerpts: dashboard.sh --donewhen's or --excerpts's one ssh command (its SSH_LIMIT, 60 s) and its check
SHOT_LIMIT = 90        # GET /shot: dashboard.sh --shot's one ssh command (its SSH_LIMIT, 60 s)
# GET /shot: a screenshot a card kept, named by its content (keepshots(), lib/push.sh); the card is a CARD id.
SHOT = re.compile(r'([0-9a-f]{40,64})\.(png|jpg|gif|webp)')
SHOT_TYPES = {'png': 'image/png', 'jpg': 'image/jpeg', 'gif': 'image/gif', 'webp': 'image/webp'}
BENCH_LIMIT = 90       # GET /bench: dashboard.sh --bench's one ssh command (its SSH_LIMIT, 60 s) and its check
ANSWER_KEYS = {'id', 'answer', 'askedAt', 'repo'}
DECISION_ID = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$')
ASKED_AT = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
# The same log ruling-log.sh appends to, under the same flock(2) lock on the file.
RULINGS = os.environ.get('CONVEYOR_RULING_LOG') or os.path.expanduser('~/.claude/rulings/conveyor.jsonl')
# Records an earlier version kept for an answer it could not pass on to main; none is written now.
UNSENT = os.path.join(os.path.dirname(RULINGS), 'dashboard-unsent')
ET = zoneinfo.ZoneInfo('America/New_York')
# The login. The store and the certificate sit beside the ruling log, outside the served folder.
AUTH = os.environ.get('CONVEYOR_DASHBOARD_AUTH') or os.path.join(os.path.dirname(RULINGS), 'dashboard-auth.json')
TLS = os.path.join(os.path.dirname(AUTH), 'dashboard-tls')
CERT, KEY = os.path.join(TLS, 'cert.pem'), os.path.join(TLS, 'key.pem')
AUDIT = os.path.join(os.path.dirname(AUTH), 'dashboard-audit.jsonl')
# The only routes a caller without a login may use (the login, and the setup link's page). Every other method and
# path is behind authed().
PUBLIC = frozenset({(m, p) for p in ('/login', '/setup') for m in ('GET', 'HEAD', 'POST')})
# The served files the login page loads before there is a login: the Board's stylesheet and icon, and its own script.
LOGIN_FILES = frozenset({'/app.css', '/icon.svg', '/login.js'})
MFA_KEY = os.path.join(os.path.dirname(AUTH), 'dashboard-mfa.key')
MFA_ISSUER = 'Conveyor'
MFA_TTL = 300  # seconds a login whose password passed waits for its code
RECOVERY_CODES = 10
NO_PASSWORD = 'no dashboard user: run dashboard_server.py add-user <user> --admin'
ROLES = ('admin', 'member')
# "No login on this device": a request from the machine the Board runs on (Handler.this_device) needs no login while
# the store's NO_LOGIN_HERE is not false (no value reads as on). It acts as an admin named LOCAL, a name no user can
# have (USER takes no space).
NO_LOGIN_HERE = 'noLoginHere'
LOCAL = 'this device'
SETUP_TTL = 86400  # a setup link works once, for a day
MAX_USERS_BODY = 1024
# scrypt N=2^14, r=8, p=5: an OWASP password-storage configuration (16 MiB, inside hashlib.scrypt's default cap).
SCRYPT = {'n': 2 ** 14, 'r': 8, 'p': 5}
USER = re.compile(r'^[A-Za-z0-9._-]{1,40}$')
SESSION_TTL, DEVICE_TTL = 43200, 31536000  # the cookies' max-age,enforced here as well
DEVICE_USED_EVERY = 600  # a device's last use is written to the store at most this often, not on every request
LOCK_AFTER, LOCK_WINDOW = 5, 900  # failed logins, and the seconds they count over and the lockout lasts
MAX_LOGIN_BODY = 4096
# One lock holds the lockout check, the scrypt compare and the failure record together, so parallel attempts cannot
# pass the count. Sessions: sha256(cookie) -> {exp, epoch, device}; memory only, so a restart logs them out.
LOGIN = threading.Lock()
SESSIONS = {}
FAILS = []
LOCKED = [0.0]
# Logins whose password passed and that wait for their code: sha256(pp_mfa cookie) -> {user, epoch, trust, label,
# exp}; memory only.
MFA_PENDING = {}
# The page a setup link opens: the token is the link's fragment, so it never travels in a request line or a Referer.
SETUP_PAGE = b'''<!doctype html><meta charset=utf-8><title>Conveyor Board: set your password</title>
<form id=f><p>Set the password you will log in with (at least 8 characters).
<p><input name=password type=password placeholder=password autocomplete=new-password minlength=8 required>
<p><input name=again type=password placeholder="password again" autocomplete=new-password minlength=8 required>
<p><button>Set password</button> <span id=m></span></form>
<script>f.onsubmit = async e => {
  e.preventDefault(); const d = new FormData(f);
  if (d.get('password') !== d.get('again')) { m.textContent = 'the two passwords differ'; return; }
  const r = await fetch('/setup', {method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({token: location.hash.slice(1), password: d.get('password')})});
  if (r.ok) location = '/login'; else m.textContent = await r.text();
};</script>
'''
# POST /control is {action, args, repo}: an action of `conveyor.sh control`, or approve, decline, retry (with --fresh:
# a blocked card's Fix), unblock (a blocked card's Hold: `conveyor.sh unblock <issue> --hold`) or close of a card,
# or build of a declined finding (the Declined panel's "File as issue": the id of its line in the record's declined list),
# or dismiss of declined findings (its "Dismiss" and "Dismiss all shown": the ids of their lines),
# or heals batch of an area's entries of the self-heals list (its Self-heals list's "File a batch card": the area, - for none),
# or heals docs of an area's entries of the docs list (its Docs list's "File a docs sweep card": the area, - for none),
# or heals harm or heals drop of entries of the self-heals list (the Self-heals page's "Move up to harm" and "Drop now": their ids),
# or depends (the Board's "Depends on…": `conveyor.sh control depends`, which writes the issue's Depends on: line on GitHub),
# or card (a card's Settings: `conveyor.sh control card`, one issue's own builder, reviewer or judge; and its Pick for
# me, `control card <issue> pick`, whose answer is the judge's settings, changing nothing),
# or full-test (the Rules tab's Run full test suite, Push landed and Push anyway: `conveyor.sh full-test [push | anyway <run id>]`),
# or push-now (the Control tab's Push now: `conveyor.sh push-now`, what landed pushed with no full test run),
# or replay (the Cost panel's judge replay study: `conveyor.sh pick replay judge <model> [<effort>] [--last <n>]
# [--estimate]`; the estimate answers its JSON, a run starts on the host and answers that it started),
# or merge-pr (the Control tab's Merge: `conveyor.sh pr merge`, the open pull request of Land as pr merged now),
# or release-run (the Release panel's buttons and Stop: `conveyor.sh release-run [prep] <version> | release-run stop <version> | release-run stop <since>`,
# and Release anyway: `release-run anyway <version> --by <Board user>`),
# or test-settings (the Tests page's limits, and one file's "slow on purpose" mark: `conveyor.sh test-settings`),
# or standing (the Rules tab's Done without asking: one standing kind of routine yes on or off, `conveyor.sh auto standing`),
# or prices (the Rules tab's Model prices: one model's price set or cleared, a model added or removed, its display name
# or an alias: `conveyor.sh prices`),
# or pick-models (the Rules tab's Pick settings: one seat's models, each with its effort range, set or cleared,
# `conveyor.sh pick models`),
# or testmap (the Tests page's Build the test map and its Stop: `conveyor.sh testmap build | stop`; an admin's alone),
# or bench (the Benchmarks tab: Start, Stop, List versions, an arm's preflight, an arm saved, Compare, and Archive,
# Restore and Delete of runs: `conveyor.sh bench swe <n> [--solo | [--arm <arm>]... [--task <id>] [--engine <version>]] [--settings
# <json>] [--again] | stop [<run id>] | runs archive|restore|delete <run id>... | versions | arms check
# [--settings <json>] <arm>... | arms save <name> <spec json> | diff <A> <B> [--json]`, an arm being a host arm's name or
# a saved revision's ID; Start and a check answer their receipt; an admin's alone),
# or card-issue (Landed today's File on GitHub on a landed card with no GitHub issue, by its card id: `conveyor.sh
# cardissue <card id>`, which answers the issue's address),
# or the Tests page's actions: testaction (`conveyor.sh testaction`: judge, explain or run one file, stop one; an
# explain sends --time <zone> <12-hour | 24-hour>, the browser's time zone and its Time setting, first), tests
# (its seat), mutate (Mutation check: `conveyor.sh mutate ask <file>...`, one ask for a list of files), testrules (Auto-file: `conveyor.sh testrules on|off|guard|set`), flaky-off (Keep a case off: `conveyor.sh
# flaky off`, which files no issue), test-close (an issue closed with a comment) and test-issue (`conveyor.sh testissue`: an issue filed about a file with the title and body sent,
# such as an Optimize issue, "Optimize the test file <file>"); testaction judge, explain or run and test-issue also take a list of
# files (test-issue: a file, title and body each), one action or issue a file, and answer JSON {results: [{file, id} or
# {file, refused}]}, one a file in the list's order,
# with its arguments as strings, each checked here before any command is built from it. Every action carries repo:
# the record of conveyor/host.json it is for (the Board and the Rules tab steer every record on the host, and Needs you
# lists every record's cards); the command then runs on that record's checkout, so an issue number is never read as
# another repository's. One with no repo (a page loaded before repo was sent) is refused, never taken as main's, and
# so is a repo the host file does not list.
MAX_CONTROL_BODY = 8192
CONTROL_KEYS = {'action', 'args', 'repo'}
REPO = re.compile(r'[A-Za-z0-9._-]+')  # a record's repo, as dashboard.sh checks it
ISSUE = re.compile(r'[1-9][0-9]{0,8}')
REDCARD = re.compile(r'c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]+-0')  # a main-red fix card, which has no issue, as conveyor.sh's retry and shut take it
CARD = re.compile(r'c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]{1,200}')  # any card id, as the engine makes it
# A seat: the CLI that runs it, then a model as that CLI names it (OpenCode's <provider>/<model> may hold / and :; a
# Claude alias may hold [1m]), one word that starts with a letter or a digit, as conveyor.sh's control takes it.
CLIS = frozenset({'claude', 'codex', 'opencode'})
MODEL = re.compile(r'[A-Za-z0-9][A-Za-z0-9._:/@\[\]-]{0,191}')
ACCOUNT = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}')  # an account name, as conveyor.sh's control takes it
EFFORTS = frozenset({'minimal', 'low', 'medium', 'high', 'xhigh', 'max'})  # claude's, codex's and opencode's, as conveyor.sh's EFFORTS
REPLAY_LAST = re.compile(r'[1-9][0-9]{0,3}')  # the reviews a judge replay takes, as conveyor.sh's pick replay --last takes them
KIND = re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]{0,39}')  # a finding kind the judge always accepts, as conveyor.sh's control takes it
CARD_SEATS = frozenset({'builder', 'reviewer', 'judge'})  # the seats one issue keeps of its own (`conveyor.sh control card`)
KINDS_MAX = 20
# The standing kinds of routine yes, as conveyor.sh's auto standing takes them (conveyor/lib/standing.sh).
STANDING = frozenset({'asked-fix', 'review-followup', 'release-check', 'fixed-block', 'review-retry'})
# An area rule is the pack's area prefix and a name: any label here; conveyor.sh checks the prefix.
# The rules Split large issues (split) and Pick settings (pick) take off, shadow or on.
RULE = re.compile(r'(split|pick)=(off|shadow|on)|(P[0-3]|followups|(?!P[0-9]+=)[A-Za-z0-9][A-Za-z0-9._:/-]{0,79})=(on|off)')
LABEL = re.compile(r'[A-Za-z0-9][A-Za-z0-9._:/-]{0,59}')
RUN_ID = re.compile(r'[0-9a-f]{12}')  # a full test run's id, as conveyor.sh's full-test anyway takes it
VERSION = re.compile(r'(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})')  # a release's, as conveyor.sh's release-run takes it
# An engine a SWE-bench run builds with, and the number of its tasks, as conveyor.sh's bench swe takes them.
BENCH_ENGINE = re.compile(r'main|v(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})|[0-9a-f]{40}')
BENCH_N = re.compile(r'[1-9][0-9]{0,2}')
# One side of a Compare, as `bench swe diff` takes it: a version, or a column's results key (an arm's name, solo-<model>,
# <arm>-<engine commit>), so two arms on one engine commit are each their own side; never one that starts with -.
BENCH_SIDE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]{0,119}')
BENCH_ARM = re.compile(r'[a-z0-9][a-z0-9-]{0,63}')  # an arm's name, as bench swe's swe_arm takes it
BENCH_ARMS_MAX = 20  # the arms one Start or one preflight check names
BENCH_RUN = re.compile(r'r[0-9]{8}T[0-9]{6}-[0-9]{1,10}')  # a run's id, as bench swe show takes it (GET /bench)
BENCH_RUNS_MAX = 100  # the runs one Archive, Restore or Delete names
BENCH_ARMID = re.compile(r'arm-[0-9a-f]{12}')  # a saved arm's revision ID, as bench swe arms save prints it
# A Start's or a check's --settings and a saved arm's spec are each one JSON object sent as one argument, of at most
# BENCH_JSON_MAX characters. Their fields are checked here as bench swe's swe_settings and swe_armsave check their shape;
# the engine still checks what only the build machine knows (its CPUs and memory, the models the project allows).
BENCH_JSON_MAX = 4096
BENCH_CPUS_MAX = 1024
BENCH_MEMORY = re.compile(r'([1-9][0-9]{0,6})([mg])')
BENCH_SETTINGS = frozenset({'revision', 'seed', 'cpus', 'memory', 'taskTimeout'})
BENCH_SEATS = frozenset({'model', 'reviewer', 'judge', 'fix', 'testFix'})
BENCH_POLICY = frozenset({'judgeOn', 'judgeAlways', 'P0', 'P1', 'P2', 'P3'})
CONTROL_CHAR = re.compile(r'[\x00-\x1f\x7f]')


def bench_json(x):
    """The JSON object one argument holds, or None: another value, NaN or Infinity, or over BENCH_JSON_MAX characters."""
    def refuse(c):
        raise ValueError(c)
    if not isinstance(x, str) or len(x) > BENCH_JSON_MAX:
        return None
    try:
        v = json.loads(x, parse_constant=refuse)
    except (ValueError, RecursionError):
        return None
    return v if isinstance(v, dict) else None


def bench_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def bench_settings_ok(x):
    """Whether x is the settings a Start or a check shares (swe_settings): an object of revision (a full commit id),
    seed (1 to 80 characters, no control character), cpus (above 0), memory (<n>m or <n>g, 512m or more) and
    taskTimeout (a whole number of seconds, 60 to 86400), each optional, and nothing else."""
    s = bench_json(x)
    if s is None or not set(s) <= BENCH_SETTINGS:
        return False
    m = BENCH_MEMORY.fullmatch(s['memory']) if isinstance(s.get('memory'), str) else None
    t = s.get('taskTimeout', 60)
    return (('revision' not in s or (isinstance(s['revision'], str) and re.fullmatch(r'[0-9a-f]{40}', s['revision']) is not None))
            and ('seed' not in s or (isinstance(s['seed'], str) and 1 <= len(s['seed']) <= 80 and not CONTROL_CHAR.search(s['seed'])))
            and ('cpus' not in s or (bench_number(s['cpus']) and 0 < s['cpus'] <= BENCH_CPUS_MAX))
            and ('memory' not in s or (m is not None and int(m[1]) * (1024 if m[2] == 'g' else 1) >= 512))
            and bench_number(t) and 60 <= t <= 86400 and t == int(t))


def bench_one_of(v, words):
    """Whether v is one of the words (a list or an object is none of them, never a TypeError)."""
    return isinstance(v, str) and v in words


def bench_seat_ok(v):
    """One seat of a saved Conveyor arm: {cli, model, effort}, effort optional."""
    return (isinstance(v, dict) and set(v) <= {'cli', 'model', 'effort'} and bench_one_of(v.get('cli'), CLIS)
            and isinstance(v.get('model'), str) and MODEL.fullmatch(v['model']) is not None and bench_one_of(v.get('effort', 'low'), EFFORTS))


def bench_spec_ok(name, x):
    """Whether name and x are a saved arm's (`bench swe arms save`, swe_armsave): a name of 1 to 80 characters with no
    control character and no space at either end, and a spec of {kind: "conveyor", seats, rules, policy} or {kind:
    "agent", recipe, cli, model, effort}, with no other field."""
    if not (isinstance(name, str) and 1 <= len(name) <= 80 and name == name.strip() and not CONTROL_CHAR.search(name)):
        return False
    s = bench_json(x)
    if s is None:
        return False
    if s.get('kind') == 'conveyor':
        seats, policy = s.get('seats', {}), s.get('policy', {})
        return (set(s) <= {'kind', 'seats', 'rules', 'policy'} and s.get('rules', 'engine') in ('engine', 'project')
                and isinstance(seats, dict) and set(seats) <= BENCH_SEATS and all(bench_seat_ok(v) for v in seats.values())
                and isinstance(policy, dict) and set(policy) <= BENCH_POLICY
                and all(isinstance(v, bool) for k, v in policy.items() if k != 'judgeAlways')
                and (lambda j: isinstance(j, list) and len(j) <= KINDS_MAX and all(isinstance(w, str) and KIND.fullmatch(w) for w in j))(policy.get('judgeAlways', [])))
    if s.get('kind') == 'agent':
        return (set(s) <= {'kind', 'recipe', 'cli', 'model', 'effort'} and isinstance(s.get('recipe'), str)
                and BENCH_ARM.fullmatch(s['recipe']) is not None and BENCH_ARMID.fullmatch(s['recipe']) is None
                and s.get('cli') in ('claude', 'codex') and isinstance(s.get('model'), str) and MODEL.fullmatch(s['model']) is not None
                and bench_one_of(s.get('effort', 'low'), EFFORTS))
    return False
# every other action: 30 s. start outlasts conveyor.sh's 60 s `timeout 60 gh issue list` (control start), so the
# panel gets the record and not a 504 while GitHub is slow; raise it with that timeout.
DECLINED_ID = re.compile(r'd[0-9a-f]{12}')  # a line of the declined list, as conveyor.sh's declined() names it
HEALS_ID = re.compile(r'h[0-9a-f]{12}')  # an entry of the self-heals list, as conveyor.sh's healsadd() names it
DOCS_ID = re.compile(r'd[0-9a-f]{12}')  # an entry of the docs list, likewise
HEALS_HARM_MAX = 10  # the most entries one heals harm files (one card each, within the heals call limit)
# depends reads the open issues and writes the issue's body, each through gh (the write under gh-write's 60 s timeout).
CONTROL_TIMEOUT = {'approve': 120, 'decline': 120, 'retry': 60, 'unblock': 60, 'close': 60,'start': 90, 'build': 60, 'heals': 60, 'depends': 120,
                   'testaction': 60, 'testmap': 60, 'test-close': 60, 'test-issue': 60, 'card-issue': 150,  # card-issue files and closes, each under gh-write's 60 s; testaction and testmap stop wait up to 40 s for the end
                   'suite-machine-check': 240,  # an ssh box's check waits for its connect, then its facts; a devbox's, for its login, its list and a box leased and given back
                   'replay': 60,  # the judge replay's estimate reads every review line of the records
                   'bench': 600,  # bench diff makes one model call a flipped task; its stop waits up to 90 s (another Stop, then the run's end)
                   'card': 360}  # Pick for me (card <issue> pick) waits up to conveyor.sh's PICK_TIMEOUT, 300 s, for the judge
DEPENDS_MAX = 20  # the issues one `control depends` names
# The condition the owner gives with their yes, or why they say no: one line of plain text.
MAX_SAID = 300


def said_ok(x):
    return isinstance(x, str) and x == x.strip() and 1 <= len(x) <= MAX_SAID and x.isprintable()


# GET /events.
PING = float(os.environ.get('CONVEYOR_DASHBOARD_PING') or 15)
MAX_FOLLOWERS = 20


class Events:
    """One feed version's events as the bytes sent: each is encoded by the first follower that sends it and kept for
    every other follower of that version."""

    def __init__(self, data):
        self.data, self.done, self.lock = data, {}, threading.Lock()

    def event(self, kind, key=None):
        """The snapshot, a panel's event (key: its id) or the updated event, encoded once."""
        with self.lock:
            if (kind, key) not in self.done:
                d = self.data
                body = (d if kind == 'snapshot' else
                        {'id': key, 'part': d['panels'][key], 'updatedAt': d.get('updatedAt')} if kind == 'panel' else
                        {'updatedAt': d.get('updatedAt')})
                self.done[(kind, key)] = ('event: %s\ndata: %s\n\n' % (kind, json.dumps(body, separators=(',', ':')))).encode()
            return self.done[(kind, key)]


class Feed:
    """data.js as the page's live feed: one thread looks at the file every 0.2 s and, when it changed, reads it whole;
    every /events client waits on the one condition for a newer version. Each panel's text (sorted keys), which a
    client compares to find the panels that changed, is worked out here once a version, not once a client; so is each
    event a client sends (Events)."""

    def __init__(self, directory):
        self.path = os.path.join(directory, 'data.js')
        self.cond = threading.Condition()
        self.version, self.data, self.texts, self.events, self.seen = 0, None, None, None, None
        self.followers = 0
        # threading is the server's, run in this namespace: globals() names it where a linter reads this file alone.
        self.loading = globals()['threading'].Lock()

    def look(self):
        # The feed's thread and each new /events page look: under one lock, a second look at a new data.js waits for
        # the first and finds it read, so the file is parsed and its version counted once, not once a caller.
        with self.loading:
            self.load()

    def load(self):
        try:
            st = os.stat(self.path)
            key = (st.st_mtime_ns, st.st_size, st.st_ino)
        except OSError:
            return
        if key == self.seen:
            return
        try:
            with open(self.path, encoding='utf-8') as f:
                text = f.read()
            data = json.loads(text[text.index('{'):text.rindex('}') + 1])
        except (OSError, ValueError):
            return  # half a file, or none: the next look reads it again
        if not isinstance(data, dict) or not isinstance(data.get('panels'), dict):
            return
        texts = {k: json.dumps(v, sort_keys=True) for k, v in data['panels'].items()}
        with self.cond:
            self.seen, self.data, self.texts, self.events, self.version = key, data, texts, Events(data), self.version + 1
            self.cond.notify_all()

    def run(self):
        while True:
            self.look()
            time.sleep(0.2)

    def wait(self, version, timeout):
        """(version, data, texts, events): the newest, once it is newer than `version` or `timeout` seconds have gone;
        texts holds each panel's text, as look() worked it out, and events its Events."""
        with self.cond:
            self.cond.wait_for(lambda: self.version != version, timeout)
            return self.version, self.data, self.texts, self.events


FEED = [None]

# The page's scripts and stylesheet (data.js among them), gzip-compressed for a browser that accepts it. Each file's
# compressed copy is made once per version of the file, not on each request: path -> ((mtime_ns, size, ino), bytes).
GZIP_TYPES = ('.js', '.css')
GZIPPED = {}
GZIP_LOCK = threading.Lock()

# GET /history: one dashboard.sh --history at a time per served folder (a second ask waits for it, then gets the copy
# it kept, with no host read): folder -> its lock. And each folder's count of POST /control actions taken: a build that
# one was taken beside drops the key it kept, as its copy may be from before the action.
HISTORY_LOCKS = {}
HISTORY_DROPS = {}
HISTORY_LOCK = threading.Lock()


def accepts_gzip(header):
    """Whether an Accept-Encoding header takes gzip: named with a q that is not 0, or, when gzip is not named, `*` so."""
    qs = {}
    for item in (header or '').split(','):
        name, _, params = item.partition(';')
        q = params.strip().lower()
        try:
            qs[name.strip().lower()] = float(q[2:]) if q.startswith('q=') else 1.0
        except ValueError:
            qs[name.strip().lower()] = 0.0
    return qs.get('gzip', qs.get('*', 0.0)) > 0


def etag(st, zipped):
    """A served file's ETag, from its os.stat st: a rewrite changes it even within the second Last-Modified counts in.
    The gzip-compressed copy is another representation of the file, so it has its own tag."""
    return '"%x-%x-%x%s"' % (st.st_mtime_ns, st.st_size, st.st_ino, '-gz' if zipped else '')


def etag_matches(header, tag):
    """Whether an If-None-Match header names tag (or is `*`), by the weak comparison that header uses."""
    for item in (header or '').split(','):
        item = item.strip()
        if item == '*' or (item[2:] if item.startswith('W/') else item) == tag:
            return True
    return False


def gzipped(path, st):
    """The gzip-compressed bytes of the file at path, whose os.stat is st: the kept copy while the file is unchanged."""
    key = (st.st_mtime_ns, st.st_size, st.st_ino)
    with GZIP_LOCK:
        kept = GZIPPED.get(path)
    if kept and kept[0] == key:
        return kept[1]
    with open(path, 'rb') as f:
        body = gzip.compress(f.read(), compresslevel=6, mtime=0)
    with GZIP_LOCK:
        GZIPPED[path] = (key, body)
    return body


def history_lock(directory):
    """The lock of GET /history's builds for the served folder directory, and its count of POST /control actions taken."""
    d = os.path.realpath(directory)
    with HISTORY_LOCK:
        return HISTORY_LOCKS.setdefault(d, threading.Lock()), HISTORY_DROPS.get(d, 0)


def drop_history_key(directory):
    """POST /control took an action: dashboard.sh --history's kept copy and its ledger key (cache/history.json and
    cache/history.key in the served folder, its OUT) are dropped, so the next GET /history builds the history again,
    with the live feed or without it."""
    d = os.path.realpath(directory)
    with HISTORY_LOCK:
        HISTORY_DROPS[d] = HISTORY_DROPS.get(d, 0) + 1
    for name in ('history.key', 'history.json'):  # the key first: a reader takes the key before the copy (kept_history)
        try:
            os.remove(os.path.join(directory, 'cache', name))
        except OSError:
            pass


def ledger_key(directory):
    """dashboard.sh's ledger_key of the live feed (stream.json in the served folder), as a list: each record's repo,
    snapshot historySum and day. None when the feed is not fresh (its stream_conv) or a record has no historySum."""
    path = os.path.join(directory, 'stream.json')
    try:
        if time.time() - os.stat(path).st_mtime > STREAM_FRESH:
            return None
        with open(path, 'rb') as f:
            feed = json.load(f)
        if not isinstance(feed.get('stream'), dict):
            return None
        key = [{'repo': r.get('repo'), 'h': (r.get('snap') or {}).get('historySum'), 'day': (r.get('snap') or {}).get('day')}
               for r in feed['records']]
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return None
    return key if all(isinstance(r['h'], str) for r in key) else None


def kept_history(directory):
    """dashboard.sh --history's kept copy (cache/history.json) and its ETag, while that script would print it with no
    host read: its kept key (cache/history.key) is the live feed's ledger key, or, with no key, the copy is under
    HISTORY_TTL seconds old. Else None. The ETag is of the key and the copy, so a copy built again for the same key
    (after a POST /control action) has a new one."""
    cache = os.path.join(directory, 'cache')
    key = ledger_key(directory)
    try:
        if key is None:
            kept = b''
            if time.time() - os.stat(os.path.join(cache, 'history.json')).st_mtime >= HISTORY_TTL:
                return None
        else:
            # The key before the copy: dashboard.sh writes the copy, then its key, and a drop removes the key first,
            # so a copy read after a matching key is never one from before it.
            with open(os.path.join(cache, 'history.key'), 'rb') as f:
                kept = f.read()
            if json.loads(kept) != key:
                return None
        with open(os.path.join(cache, 'history.json'), 'rb') as f:
            body = f.read()
        if not isinstance(json.loads(body), dict):
            return None
    except (OSError, ValueError):
        return None
    return body, '"%s"' % hashlib.sha256(kept + b'\n' + body).hexdigest()[:32]


def pick_model_ok(x):
    """Whether x is one model of a seat's pick list as `conveyor.sh pick models` takes it: <model>, or
    <model>=<min>-<max> with either bound empty (none on that side) or an effort word. The command checks that the seat
    allows the model and that its program takes the efforts."""
    if not isinstance(x, str):
        return False
    m, eq, r = x.partition('=')
    if MODEL.fullmatch(m) is None:
        return False
    if not eq:
        return True
    lo, dash, hi = r.partition('-')
    return dash == '-' and all(e == '' or e in EFFORTS for e in (lo, hi))
