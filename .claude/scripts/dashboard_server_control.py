# SPDX-License-Identifier: Apache-2.0
# A part of dashboard_server.py, run in its namespace (run_part()), not a module of its own: the checks of POST
# /control's and POST /machine's bodies, the host file, the plugin problem notes, the commands the host runs, the
# answers and the ruling log, and run_script.


def suite_word(x, first, extra, longest):
    """Whether x is one word of control suite-machine: ASCII letters and digits and the characters extra, the first
    of them a letter, a digit or one of first, at most longest long."""
    def alnum(c):
        return c.isascii() and c.isalnum()
    return 0 < len(x) <= longest and (alnum(x[0]) or x[0] in first) and all(alnum(c) or c in extra for c in x)


def suite_dir_ok(x):
    """Whether x is a folder control suite-machine --dir takes: ~, a folder under ~/ or a full path."""
    rest = x.removeprefix('~')
    return x == '~' or (len(x) <= 256 and rest.startswith('/') and all((c.isascii() and c.isalnum()) or c in '._/@+-' for c in rest))


def setup_at_ok(x):
    """Whether x is a devbox's set-up time, as control suite-machine reads it: 2026-11-20T15:04:00Z (digits and colons)."""
    digits = '0123456789'
    return (len(x) == 20 and x[4] == x[7] == '-' and x[10] == 'T' and x[19] == 'Z'
            and all(c in digits for c in x[:4] + x[5:7] + x[8:10]) and all(c in digits + ':' for c in x[11:19]))


def control_ok(body):
    """Whether the page's body is one action this route takes, with arguments of the shape conveyor.sh takes. The host
    checks again (a CLI it has not installed is refused there, with its reason)."""
    if not (isinstance(body, dict) and isinstance(body.get('action'), str)
            and set(body) == CONTROL_KEYS and isinstance(body['repo'], str) and REPO.fullmatch(body['repo'])
            and isinstance(body['args'], list) and all(isinstance(a, str) for a in body['args'])):
        return False
    a, v = body['action'], body['args']
    n = len(v)
    issues = lambda lo, hi: lo <= n <= hi and all(ISSUE.fullmatch(x) for x in v)
    if a in ('pause', 'resume', 'stop'):
        return n == 0
    if a == 'cap':
        return n == 1 and re.fullmatch(r'100|[1-9][0-9]?|off', v[0]) is not None
    if a == 'guard':
        return n == 1 and re.fullmatch(r'100|[1-9][0-9]?|off', v[0]) is not None
    if a == 'atonce':  # the test files a parallel release suite runs at once
        return n == 1 and v[0].isascii() and v[0].isdigit() and v[0][0] != '0' and len(v[0]) <= 3
    if a == 'suite-mode':  # how a release's suite runs its test files when the press names no mode
        return v in (['serial'], ['parallel'])
    if a == 'suite-machine':  # where a release's suite runs, as `control suite-machine` takes it (the host checks again)
        if v == ['local'] or v == ['devbox']:
            return True
        if v[:1] == ['devbox'] and n % 2 == 1 and n > 1:
            # --size <size> (such as 4x8), --box <a devbox the account has> and --setup-at <time> (the Board's Undo putting the
            # box's set-up time back), each once; the host checks the rest
            o = v[1::2]
            ok = {'--size': lambda x: suite_word(x, '', '._-', 20), '--box': lambda x: suite_word(x, '', '._-', 128), '--setup-at': setup_at_ok}
            return len(set(o)) == len(o) and all(k in ok and ok[k](x) for k, x in zip(o, v[2::2])) and ('--setup-at' not in o or '--size' in o)
        # An ssh target is user@host or a host, never one ssh reads as an option: it does not start with a dash.
        return v[:1] == ['ssh'] and n in (2, 4) and suite_word(v[1], '._', '._@-', 128) and (n == 2 or (v[2] == '--dir' and suite_dir_ok(v[3])))
    if a == 'suite-machine-check':  # Check the box: what the suite machine has
        return n == 0
    if a in ('hold', 'release', 'unpin'):
        return issues(1, 50)
    if a == 'order':
        return issues(0, 500)
    if a == 'rules':
        # Self-heals expiry (the days before an unfixed, unseen entry leaves the Self-heals list) goes alone: a whole
        # number from 1 to 3650, as conveyor.sh's control rules takes it.
        if any(x.startswith('healsdays=') for x in v):
            d = v[0].removeprefix('healsdays=')
            return n == 1 and d.isascii() and d.isdigit() and d[0] != '0' and len(d) <= 4 and int(d) <= 3650
        return 1 <= n <= 10 and all(RULE.fullmatch(x) for x in v)
    if a == 'judge' and v in (['on'], ['off']):  # the review's judge, on or off
        return True
    if a == 'judge' and n and v[0] == 'always':  # the finding kinds it always accepts, whole; none clears them
        return n <= 1 + KINDS_MAX and all(KIND.fullmatch(x) for x in v[1:])
    if a == 'judge' and v[:1] == ['rare']:  # the levels at which it may decline a finding as a rare case, whole; none clears them
        return v[1:] == ['none'] or (2 <= n <= 5 and all(x in ('P0', 'P1', 'P2', 'P3') for x in v[1:]))
    if a in ('model', 'reviewer', 'judge', 'tests'):  # tests: the Tests seat of the Tests page's actions
        return v == ['default'] or (n in (2, 3) and v[0] in CLIS and MODEL.fullmatch(v[1]) is not None and (n == 2 or v[2] in EFFORTS))
    if a == 'card':  # one issue's own seat: a model (the host checks the pack allows it) and an effort, or clear; or Pick for me
        if n < 2 or not ISSUE.fullmatch(v[0]):
            return False
        if v[1:] in (['clear'], ['pick']):
            return True
        return v[1] in CARD_SEATS and (v[2:] == ['clear'] or (n in (3, 4) and MODEL.fullmatch(v[2]) is not None and v[2] != 'clear' and (n == 3 or v[3] in EFFORTS)))
    if a in ('account', 'review-account'):  # one of the host file's accounts, by name (the host checks it is listed); none: no account
        return n == 0 or (n == 1 and ACCOUNT.fullmatch(v[0]) is not None)
    if a == 'start':  # where new issues start
        return v in (['queue'], ['held'])
    if a in ('dep-guard', 'push-check'):  # the dependency guard; the run before a push (default: the pack's holds)
        return v in (['on'], ['off']) or (a == 'push-check' and v == ['default'])
    if a == 'land-as':  # Land as: the push to main, or to one pull request
        return v in (['main'], ['pr'])
    if a == 'pr-merge':  # Merge PR: who merges the pull request of Land as pr
        return v in (['button'], ['release'], ['idle'])
    if a == 'merge-pr':  # Merge: the open pull request of Land as pr, merged now
        return n == 0
    if a == 'onboarded':  # the Board's setup finished: the keys of the rules the owner confirmed there
        return 1 <= n <= 40 and all(re.fullmatch(r'[a-z][A-Za-z0-9-]{0,39}', x) for x in v)
    if a == 'force':  # one waiting issue built before its dependencies land (the host refuses it while the guard is on)
        return issues(1, 1)
    if a == 'retry' and n == 2 and v[1] == '--fresh':  # a blocked card's Fix that drops its kept work, by its issue
        return ISSUE.fullmatch(v[0]) is not None
    if a in ('retry', 'close'):  # a blocked card of Needs you, or a pipeline change held there (close), by its issue; a main-red fix card by its card id
        return issues(1, 1) or (n == 1 and REDCARD.fullmatch(v[0]) is not None)
    if a == 'unblock':  # a blocked card's Hold, by its issue (conveyor.sh unblock <issue> --hold)
        return issues(1, 1)
    if a == 'build':  # a declined finding, by its line's id
        return n == 1 and DECLINED_ID.fullmatch(v[0]) is not None
    if a == 'dismiss':  # declined findings, by their lines' ids ("Dismiss", "Dismiss all shown"); as many as fit the body
        return 1 <= n <= 400 and all(DECLINED_ID.fullmatch(x) for x in v)
    if a == 'heals':  # the Self-heals list's "File a batch card" (batch), the Docs list's "File a docs sweep card" (docs): an area's label, or - for the entries with none
        if n >= 2 and v[0] in ('harm', 'drop'):  # the Self-heals page's "Move up to harm" (one card each: at most HEALS_HARM_MAX) and "Drop now": entry ids
            return n - 1 <= (globals()['HEALS_HARM_MAX'] if v[0] == 'harm' else 400) and all(globals()['HEALS_ID'].fullmatch(x) for x in v[1:])  # the base part's
        if not (n >= 2 and v[0] in ('batch', 'docs') and (v[1] == '-' or globals()['LABEL'].fullmatch(v[1]) is not None)):  # the base part's
            return False
        # The batch sheet's: --held or --queue, --prio P2|P3, --title <text>, in that order, then the entries it keeps (of its list).
        rest = v[2:]
        if rest[:1] in (['--held'], ['--queue']):
            rest = rest[1:]
        if rest[:1] == ['--prio']:
            if len(rest) < 2 or rest[1] not in ('P2', 'P3'):
                return False
            rest = rest[2:]
        if rest[:1] == ['--title']:
            if len(rest) < 2 or not globals()['said_ok'](rest[1]) or len(rest[1]) > 200:  # the base part's
                return False
            rest = rest[2:]
        entry = globals()['DOCS_ID'] if v[0] == 'docs' else globals()['HEALS_ID']  # the base part's
        return len(rest) <= 400 and all(entry.fullmatch(x) for x in rest)
    if a in ('approve', 'decline'):  # the issue, then a condition (approve) or a reason (decline), if any
        return 1 <= n <= 2 and ISSUE.fullmatch(v[0]) is not None and (n == 1 or said_ok(v[1]))
    if a == 'unlabel':  # the issue and the labels that hold it back
        return 2 <= n <= 6 and ISSUE.fullmatch(v[0]) is not None and all(LABEL.fullmatch(x) for x in v[1:])
    if a == 'depends':  # the issue, add or remove, then 1 to DEPENDS_MAX issues of its Depends on: line (the host checks each)
        return 3 <= n <= 2 + DEPENDS_MAX and ISSUE.fullmatch(v[0]) is not None and v[1] in ('add', 'remove') and all(ISSUE.fullmatch(x) for x in v[2:])
    if a == 'full-test':  # Run full test suite (none), Push landed (push), Push anyway over the red run shown (anyway, its id)
        return v in ([], ['push']) or (n == 2 and v[0] == 'anyway' and RUN_ID.fullmatch(v[1]) is not None)
    if a == 'push-now':  # Push now: what landed, pushed through the pre-push hook only, with no full test run
        return n == 0
    if a == 'release-run':  # the Release panel's Release (the version typed), Draft notes and Run suite (prep, the version),
        # Release anyway over release-prep's red suite (anyway, the version) and Stop (stop, the version of the run the panel
        # shows: the engine stops no run of another version, so a late Stop never stops a later run of another version; a
        # later run of the same version it still stops; or stop <since> of a wait). Release and prep may end in
        # the suite's mode, --serial or --parallel (the owner's choice when the press runs the suite), then, last, `--machine
        # local` (the owner's choice to run that suite here, whatever the rule's machine is).
        if n >= 3 and v[-2:] == ['--machine', 'local'] and v[0] not in ('stop', 'anyway'):
            v, n = v[:-2], n - 2
        if n >= 2 and v[-1] in ('--serial', '--parallel') and v[0] not in ('stop', 'anyway'):
            v, n = v[:-1], n - 1
        version = globals()['VERSION']  # the base part's, as REDCARD is below
        # Stop of a run that waits on its notes card names that run's start (`stop <since>`), so a late one ends no suite.
        # (ASKED_AT is the base part's too.)
        if n == 2 and v[0] == 'stop' and globals()['ASKED_AT'].fullmatch(v[1]) is not None:
            return True
        return (n == 1 and version.fullmatch(v[0]) is not None) or (n == 2 and v[0] in ('prep', 'anyway', 'stop') and version.fullmatch(v[1]) is not None)
    if a == 'test-settings':  # the Tests page: a test limit of the pack, or one file's mark
        return test_settings_ok(v)
    if a == 'standing':  # the Rules tab: one standing kind of routine yes, on or off
        return n == 2 and v[0] in STANDING and v[1] in ('on', 'off')
    if a == 'pick-models':  # the Rules tab's Pick settings: one seat's models, each <model>[=<min>-<max>], or clear
        return n >= 2 and v[0] in ('builder', 'reviewer', 'judge') and (v[1:] == ['clear'] or ('clear' not in v[1:] and all(pick_model_ok(x) for x in v[1:])))
    if a == 'prices':  # the Rules tab's Model prices: one model's price, added model, display name or alias
        return n >= 2 and MODEL.fullmatch(v[1]) is not None and (
            (n in (5, 6) and v[0] == 'set' and all(PRICE.fullmatch(x) for x in v[2:]))
            or (n == 2 and v[0] in ('clear', 'remove'))
            or (n in (7, 8) and v[0] == 'add' and v[2] in PROVIDERS and NAME.fullmatch(v[3]) is not None and all(PRICE.fullmatch(x) for x in v[4:]))
            or (n in (2, 3) and v[0] == 'name' and all(NAME.fullmatch(x) for x in v[2:]))
            or (n == 4 and v[0] == 'alias' and v[2] in ('add', 'remove') and MODEL.fullmatch(v[3]) is not None))
    if a == 'testaction':  # the Tests page: judge, explain or run one test file or a list of them, or stop one action by
        # its id; an explain with --time, the zone and Time setting of the browser that asked, which its facts' times are in
        if n >= 5 and v[:2] == ['explain', '--time']:
            return ZONE.fullmatch(v[2]) is not None and v[3] in ('12-hour', '24-hour') and n <= 4 + TEST_FILES_MAX \
                and all(TEST_FILE.fullmatch(x) for x in v[4:])
        return (2 <= n <= 1 + TEST_FILES_MAX and v[0] in ('judge', 'explain', 'run') and all(TEST_FILE.fullmatch(x) for x in v[1:])) \
            or (n == 2 and v[0] == 'stop' and RUN_ID.fullmatch(v[1]) is not None)
    if a == 'testmap':  # the Tests page's Build the test map, or its Stop
        return v in (['build'], ['stop'])
    if a == 'bench':  # `bench swe`: Start (n, then --solo, or arms and a version, then the shared settings), Stop, List versions, an arm's preflight, an arm saved, Compare (two versions or results keys); the Benchmarks tab sends Start with n and arms, Stop, preflights, the runs' Archive, Restore and Delete, and Compare
        if v in (['stop'], ['versions']):
            return True
        if v[:1] == ['stop']:  # Stop of the run the tab shows, by its id: a late one never stops the run after it
            return n == 2 and BENCH_RUN.fullmatch(v[1]) is not None
        if v[:1] == ['runs']:  # Archive, Restore and Delete of the runs named (one, or the runs selected)
            return (3 <= n <= 2 + BENCH_RUNS_MAX and v[1] in ('archive', 'restore', 'delete')
                    and all(BENCH_RUN.fullmatch(x) for x in v[2:]))
        if v[:1] == ['diff']:
            return n in (3, 4) and all(BENCH_SIDE.fullmatch(x) for x in v[1:3]) and v[3:] in ([], ['--json'])
        if v[:2] == ['arms', 'save']:
            return n == 4 and bench_spec_ok(v[2], v[3])
        if v[:2] == ['arms', 'check']:
            arms = v[2:]
            if arms[:1] == ['--settings']:
                if not (len(arms) >= 2 and bench_settings_ok(arms[1])):
                    return False
                arms = arms[2:]
            return 1 <= len(arms) <= BENCH_ARMS_MAX and all(BENCH_ARM.fullmatch(x) for x in arms)
        if not (n >= 2 and v[0] == 'run' and BENCH_N.fullmatch(v[1]) is not None and int(v[1]) <= 500):
            return False
        rest, arms = v[2:], 0
        if rest[-1:] == ['--again']:  # a task's Run again: its results are kept apart from the saved ones
            rest = rest[:-1]
        if rest[-2:-1] == ['--settings']:
            if not bench_settings_ok(rest[-1]):
                return False
            rest = rest[:-2]
        if rest == ['--solo']:
            return True
        while rest[:1] == ['--arm'] and len(rest) >= 2 and BENCH_ARM.fullmatch(rest[1]) is not None:
            rest, arms = rest[2:], arms + 1
        if rest[:1] == ['--task']:  # a task's Run again: that one task, never the first n (n is then 1)
            t = rest[1] if len(rest) >= 2 else ''  # an id: ASCII letters, digits, . _ -, up to 120, never starting with -
            if not (v[1] == '1' and 1 <= len(t) <= 120 and t.isascii() and t[0].isalnum() and all(c.isalnum() or c in '._-' for c in t)):
                return False
            rest = rest[2:]
        return arms <= BENCH_ARMS_MAX and (rest == [] or (len(rest) == 2 and rest[0] == '--engine' and BENCH_ENGINE.fullmatch(rest[1]) is not None))
    if a == 'mutate':  # the Tests page's Mutation check: one test file or a list of them, to the front of the idle queue
        return 1 <= n <= TEST_FILES_MAX and all(TEST_FILE.fullmatch(x) for x in v)
    if a == 'testrules':  # the Tests page's Auto-file: the switch, a guard, or one setting of a rule
        return (v in (['on'], ['off']) or (n == 3 and v[0] == 'guard' and v[1] in RULE_GUARDS and RULE_VALUE.fullmatch(v[2]) is not None)
                or (n == 4 and v[0] == 'set' and said_ok(v[1]) and v[2] in RULE_KEYS and RULE_VALUE.fullmatch(v[3]) is not None))
    if a == 'flaky-off':  # Keep a case off: "<test file>: <case>", then why
        return n == 2 and said_ok(v[0]) and said_ok(v[1]) and TEST_FILE.fullmatch(v[0].split(': ', 1)[0]) is not None and ': ' in v[0]
    if a == 'test-close':  # Close its issue as done, or put back a flaky case (its flaky issue closed): the issue, then the comment
        return n == 2 and ISSUE.fullmatch(v[0]) is not None and said_ok(v[1])
    if a == 'replay':  # the Cost panel's judge replay study: a model, an effort if any, --last <n> if any, then --estimate if asked
        if v[-1:] == ['--estimate']:
            v, n = v[:-1], n - 1
        if n >= 3 and v[-2] == '--last' and REPLAY_LAST.fullmatch(v[-1]) is not None:
            v, n = v[:-2], n - 2
        return n in (1, 2) and MODEL.fullmatch(v[0]) is not None and (n == 1 or v[1] in EFFORTS)
    if a == 'test-issue':  # File an issue about a test file, or one about each of a list: the file, the title, then the body the owner read and edited
        return n % 3 == 0 and 3 <= n <= 3 * TEST_FILES_MAX and all(
            TEST_FILE.fullmatch(f) is not None and said_ok(t) and len(t) <= 200 and 1 <= len(b.strip()) and len(b) <= TEST_ISSUE_BODY
            and all(line.isprintable() for line in b.split('\n')) for f, t, b in zip(v[0::3], v[1::3], v[2::3]))
    if a == 'card-issue':  # Landed today's File on GitHub on a landed card with no GitHub issue, by its card id
        # (REDCARD comes from the base part, run in this namespace: globals() names it where a linter reads this file alone.)
        return n == 1 and globals()['REDCARD'].fullmatch(v[0]) is not None
    return False


def test_files(action, args):
    """A Tests page action on a list of files (testaction judge, explain or run, test-issue), as (file, the arguments of
    the action on that file alone) for each: control() runs each on its own, as the action on one file, and answers
    each on its own. None for any other action, and for one on a single file, answered as before."""
    if action == 'testaction' and args[0] != 'stop':
        k = 4 if args[1:2] == ['--time'] else 1  # an explain's --time goes with each file
        each = [(f, args[:k] + [f]) for f in args[k:]]
    elif action == 'test-issue':
        each = [(f, [f, t, b]) for f, t, b in zip(args[0::3], args[1::3], args[2::3])]
    else:
        each = []
    return each if len(each) > 1 else None


# The Auto-file guards and settings of a rule, and a value of one, as `conveyor.sh testrules` takes them (it checks each).
RULE_GUARDS = frozenset({'perDay', 'maxOpen', 'quietDays', 'burst'})
RULE_KEYS = frozenset({'on', 'measure', 'limit', 'runs', 'minRuns', 'days', 'minClock'})
RULE_VALUE = re.compile(r'true|false|usual|clock|flaky|failed|[0-9]{1,6}(\.[0-9]{1,3})?')
TEST_ISSUE_BODY = 2500  # the most characters of an issue body the Tests page files: 3 bytes each still fit MAX_CONTROL_BODY
# The most files of one Tests page action on a list of files; such a body may be TEST_FILES_MAX times MAX_CONTROL_BODY.
TEST_FILES_MAX = 20
MAX_TEST_LIST_BODY = TEST_FILES_MAX * MAX_CONTROL_BODY


# A test file's path from the repository root, as the Tests page sends it (the host checks that main's checkout tracks
# it); never one that starts with - or /.
TEST_FILE = re.compile(r'[A-Za-z0-9._@+][A-Za-z0-9._@+/-]{0,299}')
# A browser's time zone, as its IANA name (America/New_York, Etc/GMT+5), as `conveyor.sh testaction explain --time` takes it.
ZONE = re.compile(r'(?=.{1,64}$)[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*')
# A price as typed, one word: `conveyor.sh prices set` checks it is $ per million tokens and says why it is not, so the
# Rules tab shows the refusal (a negative or a word) in the engine's own words.
PRICE = re.compile(r'\S{1,40}')
# A model's display name (`conveyor.sh prices name` and add): 1 to 60 characters with no control character; and the
# group an added model shows in.
NAME = re.compile(r'[^\x00-\x1f\x7f]{1,60}')
PROVIDERS = frozenset({'claude', 'openai', 'opencode', 'other'})


def test_settings_ok(v):
    """Whether args are one `conveyor.sh test-settings` command: slow-issues true|false, slow-mark <file> <reason: one
    line>, slow-mark-clear <file>, cpu-time <file> (Record CPU time: the pack's test command changed, an admin's
    alone), record-times (Record test times: the engine's plan run, an admin's alone) or history-start <UTC time like
    2026-11-21T00:00:00Z | clear> (the control record's test history start)."""
    n, w = len(v), v[0] if v else None
    if n == 1 and w == 'record-times':
        return True
    if n == 2 and w == 'slow-issues':
        return v[1] in ('true', 'false')
    if n == 3 and w == 'slow-mark':
        return TEST_FILE.fullmatch(v[1]) is not None and said_ok(v[2])
    if n == 2 and w in ('slow-mark-clear', 'cpu-time'):
        return TEST_FILE.fullmatch(v[1]) is not None
    if n == 2 and w == 'history-start':
        return v[1] == 'clear' or setup_at_ok(v[1])  # the command checks the date itself
    return False


def machine_ok(body):
    """Whether the page's body is one machine action POST /machine takes: {action: pause | resume} and nothing else.
    It names no project: an action for a project goes to /control, which refuses one without its repo."""
    if not isinstance(body, dict):
        return False
    return set(body) == {'action'} and body['action'] in ('pause', 'resume')


def board_main():
    """This machine's checkout, by dashboard.sh's rule: CONVEYOR_MAIN, else git. ValueError when it cannot be found."""
    main = os.environ.get('CONVEYOR_MAIN')
    if main:
        return main
    try:
        common = subprocess.run(['git', '-C', HERE, 'rev-parse', '--path-format=absolute', '--git-common-dir'],
                                capture_output=True, text=True, timeout=10, check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError) as e:
        raise ValueError('the main checkout could not be found') from e
    return common[:-5] if common.endswith('/.git') else common


def host_path():
    """The conveyor/host.json dashboard.sh reads: this machine's host file when there is one (dashboard.sh's conveyor()
    rule), else the committed one of this machine's checkout (board_main()). ValueError when no checkout is found."""
    host_file = os.path.join(os.environ.get('XDG_CONFIG_HOME') or os.path.expanduser('~/.config'), 'conveyor', 'host.json')
    return host_file if os.path.exists(host_file) else os.path.join(board_main(), 'conveyor', 'host.json')


def host_file():
    """conveyor/host.json as dashboard.sh reads it (host_path()). ValueError when it does not read."""
    try:
        with open(host_path()) as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise ValueError('conveyor/host.json is missing or not understood') from e


PLUGIN_ROOT = os.path.dirname(os.path.dirname(HERE))  # the checkout this Board runs from
NOTE_LINE = re.compile(r'- (?P<at>\S+) · card (?P<card>\S+) · (?P<text>.*)')  # a plugin-bugs.md note (foreman/stop.sh)
# A note that names the issue it was filed as (foreman/stop.sh's and foreman.sh's test): it is not filed again.
# The note's guessed cause (foreman/stop.sh's "cause not checked: <text>" part): it ends at the card, evidence or filed part, each in its own shape, a card id or "-", a path or "-" (so a cause that says ", card lookups" goes on).
NOTE_CAUSE = globals()['re'].compile(r'(?:, |^)cause not checked: (?P<cause>.*?)(?=, card (?:(?:c[0-9]{8}T[0-9]{6}-|<card>)\S*|-)(?:, |$)|, evidence (?:\S*/\S*|-)(?:, |$)|, filed as #|$)', globals()['re'].I)  # re is the base part's, as CARD is
NOTE_FILED = globals()['re'].compile(r'[\s,;]filed as #[1-9][0-9]*\s*\.? · evidence: ', globals()['re'].I)  # re is the base part's, as above
# Any card id a note's text or evidence names (its card field's, or another card's, or a card's evidence file name): it
# ends at its last '-<issue or lane>' part, so a file's extension (c...-alpha-7.err) and the stop that ends a sentence
# (see c...-alpha-7.) stay out of it.
NOTE_CARDS = globals()['re'].compile(r'(?<![A-Za-z0-9])c[0-9]{8}T[0-9]{6}-[A-Za-z0-9._-]*?-[A-Za-z0-9]+(?=\.[A-Za-z]+\b|[._-]*(?:[^A-Za-z0-9._-]|$))')  # re as above


def note_issue(line):
    """The issue a Plugin problems note proposes, as (title, body): the title is the note's first clause (its text before
    the first ' · ', cut at the first , ; : or . that ends a clause); the body is the note, then the plugin's version,
    the engine commit and the system of the checkout this Board runs from. Card ids stay out: one names a project, so
    each card id the note's text or evidence says (its own card's, another card it compares, a card's evidence file
    name), whatever its card field is, is <card> in the body. An issue number names no project and stays.
    The note's ' · evidence: <path>' part (the last one, as foreman/stop.sh reads it) is not in the body as it is: the
    body has the text alone when the text already names the path (or the part is '-' or not there), else the text and
    a line 'Evidence: <path>'. The note's 'cause not checked: <text>' part is not in the text: the body has it as its
    own last line 'Cause (not checked): <text>', and has no such line when the note has no such part."""
    m = NOTE_LINE.fullmatch(line)
    text = m.group('text') if m else line[2:]
    text, sep, evidence = text.rpartition(' · evidence: ')
    if not sep:
        text, evidence = evidence, ''
    evidence = evidence.strip()
    text, evidence = NOTE_CARDS.sub('<card>', text), NOTE_CARDS.sub('<card>', evidence)
    cause = NOTE_CAUSE.search(text)
    claim = text
    if cause:
        claim = text[:cause.start()].strip(', ')
        text = (text[:cause.start()] + text[cause.end():]).lstrip(', ')
        if not claim:  # the hook put the whole claim in the cause (a [likely] tag): the title is from it, not 'card <card>'
            claim = cause.group('cause')
    title = globals()['re'].split(r'[,;:.](?=\s|$)', claim.split(' · ')[0], maxsplit=1)[0].strip() or 'Plugin problem'
    if evidence not in ('', '-') and evidence not in text:  # after the title: the Evidence line is no part of it
        text += '\nEvidence: ' + evidence
    if cause and cause.group('cause').strip():
        text += '\nCause (not checked): ' + cause.group('cause').strip()
    try:
        with open(os.path.join(PLUGIN_ROOT, '.claude-plugin', 'plugin.json'), encoding='utf-8') as f:
            version = json.load(f).get('version')
    except (OSError, ValueError, AttributeError):
        version = None
    try:
        commit = subprocess.run(['git', '-C', PLUGIN_ROOT, 'rev-parse', 'HEAD'], capture_output=True, text=True,
                                timeout=10, check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        commit = ''
    body = '%s\n\n%sPlugin version: %s\nEngine commit: %s\nSystem: %s %s %s\n' % (
        text, 'Noted: %s\n' % m.group('at') if m else '', version if isinstance(version, str) and version else 'not known',
        commit or 'not known', platform.system(), platform.release(), platform.machine())
    return title, body


def plugin_repo():
    """The owner/name of the GitHub repository .claude-plugin/plugin.json names (its repository), where a plugin
    problem is filed. ValueError when it names none."""
    try:
        with open(os.path.join(PLUGIN_ROOT, '.claude-plugin', 'plugin.json'), encoding='utf-8') as f:
            url = json.load(f).get('repository')
    except (OSError, ValueError, AttributeError) as e:
        raise ValueError('.claude-plugin/plugin.json does not read') from e
    m = re.fullmatch(r'https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?', url) if isinstance(url, str) else None
    if not m:
        raise ValueError('.claude-plugin/plugin.json names no GitHub repository')
    return m.group(1)


def privacy_hits(title, body):
    """conveyor/privacy/check.sh on the title (line 1) and the body (the lines after it), with the host file's terms
    file as gh_write reads it (lib/issues.sh): each hit as 'the title: <pattern>' or 'body line <n>: <pattern>', never
    the matched text. ValueError when the check could not be made, which files nothing either. As in gh_write, a host
    file that is there but does not read may name a terms file, so it fails the check; only a missing one means no terms."""
    try:
        cfg = host_file()
    except ValueError:
        if os.path.exists(host_path()):
            raise ValueError("the host file does not read, so its terms file cannot be read") from None
        cfg = None
    terms = cfg.get('terms') if isinstance(cfg, dict) else None
    if terms:
        terms = os.path.expanduser(terms) if isinstance(terms, str) and terms.startswith('~/') else terms
        if not (isinstance(terms, str) and os.path.isfile(terms) and os.access(terms, os.R_OK)):
            raise ValueError("the host file's terms file cannot be read")
    try:
        r = subprocess.run(['bash', os.path.join(PLUGIN_ROOT, 'conveyor', 'privacy', 'check.sh')] + (['--terms', terms] if terms else []),
                           input=title + '\n' + body + '\n', capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        raise ValueError('the privacy check could not run') from e
    hits = [re.fullmatch(r'-:([0-9]+): (.+)', x) for x in r.stdout.splitlines()]
    if r.returncode not in (0, 1) or not all(hits) or (r.returncode == 1) != bool(hits):
        raise ValueError('the privacy check failed')
    return ['the title: %s' % h.group(2) if h.group(1) == '1' else 'body line %d: %s' % (int(h.group(1)) - 1, h.group(2)) for h in hits]


def record_ledger(repo):
    """The decision ledger the host file's record for repo names (records[].ledger), the one dashboard.sh read the
    decision from; the page names only the record, never a path. ValueError when that record names none."""
    cfg = host_file()
    recs = cfg.get('records') if isinstance(cfg, dict) else None
    led = next((r.get('ledger') for r in recs if isinstance(r, dict) and r.get('repo') == repo), None) if isinstance(recs, list) else None
    if not (isinstance(led, str) and led):
        raise ValueError('conveyor/host.json names no decision ledger for %s' % repo)
    return led


def conveyor_host():
    """(host, ssh target, the checkout whose conveyor.sh runs, {repo: checkout} of its records) from conveyor/host.json,
    as hostfile.sh, its one reader, gives it for this machine's checkout (board_main()). On one machine the target is
    None and the Board's own copy of Conveyor runs here; with a build machine it is the host's main. ValueError naming
    the field that is wrong when it does not say."""
    got = read_host_file(board_main())
    return got['host'], got['target'], got['engine'], {r['repo']: r['main'] for r in got['records']}


def read_host_file(main):
    """hostfile.sh's answer for the checkout main: {host, main, engine, target, records}. ValueError with its reason
    when the host file does not say them."""
    try:
        run = subprocess.run(['bash', os.path.join(HERE, 'hostfile.sh'), main], capture_output=True, text=True, timeout=30)
        got = json.loads(run.stdout)
    except (OSError, subprocess.SubprocessError, ValueError) as e:
        raise ValueError('conveyor/host.json could not be read: %s' % e) from e
    if run.returncode != 0 or not isinstance(got, dict) or got.get('error') is not None:
        raise ValueError(got.get('error') if isinstance(got, dict) and got.get('error') else 'conveyor/host.json could not be read')
    return got


def control_script(action, args, main, today, record=None, user=None):
    """The command the host runs for one checked action. Every value is quoted, though each was checked already.
    approve and decline act only on a card blocked for the owner's yes (the health record's waiting), or on an issue waiting
    for their yes before its build (its before): approve writes the approval line on the issue (who, the date, the Board
    user who said yes, and the condition they gave, if any), then retries the card, which resumes from its kept patch; decline posts
    the owner's reason on the issue (when they gave one), holds the issue, then retries the card, so it waits under Held with
    its patch kept and is not built until it is released. An issue waiting before its build has no card to retry:
    approved, it is picked in its turn; declined, it is held. unlabel ("Remove the label and queue it", after the owner
    confirmed it on the Board) removes the labels that hold the issue back, on GitHub, then releases the issue, so
    the record holds it no more either; the reply is the record. close ("Close" on a blocked card of Needs you, or on a pipeline change
    held there, once the owner confirmed it) closes the issue with a comment that says so, then shuts its blocked card, if any (conveyor.sh shut). build files a declined finding of the record's list
    as an ordinary issue (conveyor.sh declined build: once, however often it is asked); dismiss marks lines of that list
    dismissed by the Board user, so they leave the Declined panel (conveyor.sh declined dismiss); heals batch files one
    card with an area's entries of the self-heals list as its scope (conveyor.sh heals batch), and heals docs one docs
    sweep card with an area's entries of the docs list (conveyor.sh heals docs); heals harm files each entry of the
    self-heals list named as its own follow-up and takes it off the list, heals drop takes them off (conveyor.sh heals
    harm, heals drop). record is the checkout of the record the action
    is for: every action runs on its Conveyor record (and approve, decline and unlabel in its GitHub repository), never
    main's unless it is main's.
    The script itself is always main's, as dashboard.sh runs it for every record. Every GitHub write goes through its
    gh-write (the privacy gate, plan section 8, P5); a refused write fails the command, so the Board shows the error."""
    q = shlex.quote
    conv = 'CONVEYOR_MAIN=%s bash %s' % (q(record or main), q(main + '/conveyor/conveyor.sh'))
    if action == 'retry':
        return '%s retry %s' % (conv, ' '.join(q(x) for x in args))
    if action == 'unblock':
        # Hold on a blocked card of Needs you: its issue held and its card given back, its kept work kept.
        return '%s unblock %s --hold' % (conv, q(args[0]))
    if action == 'close':
        # Close on a blocked card of Needs you: its issue, closed in the record's repository, then its blocked card shut
        # (closed in the card records) at once, as the loop's next turn would, so it leaves Needs you though the loop is
        # stopped, and pick never takes it from an open list asked before it closed. Never retry it here: that gives
        # the card back, and the loop can pick the closed issue again. A pipeline change held there has no card: shut
        # leaves the records as they are and exits 4 (it shut nothing), which is no failure of the Close, and the
        # closed issue leaves the snapshot's list of open held follow-ups. Any other failure of shut (exit 1 when the
        # records could not be locked, read or written) fails the Close, so the Board shows it. shut is told the issue
        # was closed (--closed): without it, shut takes the card as the owner's, and no turn gives it back once the
        # issue is opened again.
        # A main-red fix card has no issue to close: it is shut alone, by its card id.
        if REDCARD.fullmatch(args[0]):
            return '%s shut %s' % (conv, q(args[0]))
        said, n = q("Closed from the Board's Needs you list."), q(args[0])
        return f'cd {q(record or main)} || exit 1; {conv} gh-write issue close {n} --comment {said} >/dev/null && {{ {conv} shut {n} --closed || [ $? = 4 ]; }}'
    if action == 'suite-machine-check':
        # The check's JSON line is the answer. It exits 1 when a need is missing, which is the answer too; with no
        # output (the rule cannot be read) the command's own error is the answer.
        # A devbox's check asks the account for a box, which can create one: only an admin's check does; a member's reads.
        flag = '' if user and globals()['is_admin'](user) else ' --no-create'
        return f'o=$({conv} suite-machine check --json{flag}) || [ $? = 1 ]; [ -n "$o" ] || exit 1; printf "%s\\n" "$o"'
    if action == 'build':
        return '%s declined build %s' % (conv, q(args[0]))
    if action == 'dismiss':
        return '%s declined dismiss --by %s %s' % (conv, q('Board user %s' % user), ' '.join(q(x) for x in args))
    if action == 'heals':
        sub = args[0] if args[0] in ('docs', 'harm', 'drop') else 'batch'
        return f'{conv} heals {sub} ' + ' '.join(q(x) for x in args[1:])
    if action == 'full-test':
        # The run goes on on the host after the answer (conveyor.sh full-test starts it and returns); a push over a red
        # suite names the red run the confirm showed and is logged under the Board user who confirmed it.
        return '%s full-test%s%s' % (conv, ''.join(' ' + q(x) for x in args), ' --by %s' % q('Board user %s' % user) if args[:1] == ['anyway'] else '')
    if action == 'merge-pr':
        # The merge is GitHub's answer: a refusal fails the command, so the Board shows GitHub's reason.
        return '%s pr merge' % conv
    if action == 'push-now':
        # The push goes on on the host after the answer (conveyor.sh push-now starts it and returns).
        return '%s push-now' % conv
    if action == 'replay':
        # The estimate answers at once and calls no model. A run calls the judge once a review, which takes minutes:
        # its arguments are checked by an estimate first (a refusal is the answer), then it goes on on the host after
        # the answer, and its result reaches the Cost panel with the next snapshot.
        said = ' '.join(q(x) for x in args)
        if args[-1] == '--estimate':
            return '%s pick replay judge %s' % (conv, said)
        return ('%s pick replay judge %s --estimate > /dev/null && { nohup env %s pick replay judge %s > /dev/null 2>&1 < /dev/null & '
                'echo "conveyor: the judge replay started; the Cost panel shows its result when it ends"; }') % (conv, said, conv, said)
    if action == 'release-run':
        # Release: the owner's yes to release-prep, then release, which run on the host after the answer; prep: release-prep
        # alone (Draft notes, Run suite); or Stop. A release over a red suite (anyway) is logged under the Board user who
        # confirmed it.
        return '%s release-run %s%s' % (conv, ' '.join(q(x) for x in args), ' --by %s' % q('Board user %s' % user) if args[:1] == ['anyway'] else '')
    if action in ('test-settings', 'prices'):
        # The record's pack (.conveyor/project.json of its main), changed by the engine's own command, which checks it.
        return '%s %s %s' % (conv, action, ' '.join(q(x) for x in args))
    if action == 'pick-models':
        # The record's pack's pick: one seat's list set or cleared (conveyor.sh pick models, which checks it).
        return '%s pick models %s' % (conv, ' '.join(q(x) for x in args))
    if action == 'standing':
        # The record's pack's auto.standing: one kind on or off (conveyor.sh auto standing, which checks it).
        return '%s auto standing %s %s' % (conv, q(args[0]), q(args[1]))
    if action == 'bench':
        if args[0] == 'run' or args[:2] == ['arms', 'check']:
            # A run takes hours, and an arm's preflight minutes: it starts on the host and goes on after the answer. The
            # answer is its receipt, the lines the engine prints once it has recorded the admission: a run's
            # "conveyor: run <id> started", and for each arm checked "<arm>: checking <check id>" (or "<arm>: waiting
            # ...", behind another request's check). One the engine ends before that (a run already going, the usage
            # guard reached, an arm or saved revision not there, a version it cannot take) answers its refusal on
            # stderr, the stream the handler reads when a script fails; one that ends well with no receipt (a run that
            # reuses each task's saved result prints none) answers its output on stdout, the stream the handler reads
            # when a script succeeds. Once the receipt is printed, the answer is the receipt alone, whether or not the
            # work has ended since: its end is in its record, so the answer does not depend on when the poll reads the log.
            if args[0] == 'run':
                rest, said = args[1:], "grep -E '^conveyor: run r[0-9]{8}T[0-9]{6}-[0-9]+ started$' \"$l\""
            else:
                names = args[4:] if args[2:3] == ['--settings'] else args[2:]
                rest, said = args, ' && '.join("grep -E '^%s: (checking|waiting) ' \"$l\"" % x for x in dict.fromkeys(names))
            return ('l=$(mktemp) || exit 1; %s bench swe %s > "$l" 2>&1 < /dev/null & p=$!; '
                    'while kill -0 "$p" 2>/dev/null && ! { %s; } > /dev/null; do sleep 0.2; done; '
                    'if a=$(%s); then printf "%%s\\n" "$a"; rm -f "$l"; '
                    'else wait "$p"; r=$?; if [ "$r" = 0 ]; then cat "$l"; else cat "$l" >&2; fi; rm -f "$l"; exit "$r"; fi') % (conv, ' '.join(q(x) for x in rest), said, said)
        return '%s bench swe %s' % (conv, ' '.join(q(x) for x in args))
    if action in ('testaction', 'testrules', 'testmap'):
        # A test action starts on the host and returns its id (conveyor.sh testaction); a rule's change is the pack's;
        # a build of the test map starts on the host and returns (conveyor.sh testmap build), or is stopped.
        return '%s %s %s' % (conv, action, ' '.join(q(x) for x in args))
    if action == 'mutate':
        # One ask for all the files (conveyor.sh mutate ask): it starts no check; the idle job does, when no card needs a slot.
        return '%s mutate ask %s' % (conv, ' '.join(q(x) for x in args))
    if action == 'flaky-off':
        # An entry of the flaky-test record keeps the case off card test steps; its source names the Board user. flaky
        # off, not add: the action is marked "now" and files no issue, though the entry is a case's third source.
        return '%s flaky off %s %s %s' % (conv, q(args[0]), q('Board user %s' % user), q(args[1]))
    if action == 'test-close':
        return 'cd %s || exit 1; %s gh-write issue close %s --comment %s' % (q(record or main), conv, q(args[0]), q(args[1]))
    if action == 'card-issue':
        # The engine files the issue from the card's record (its title and body), closes it naming the commit the card
        # landed as, and answers its address.
        return f'cd {q(record or main)} || exit 1; {conv} cardissue {q(args[0])}'
    if action == 'test-issue':
        # The engine files it (the pack's type and last priority) and keeps it for the file's row: Close its issue as done.
        # The owner pressed the button: the Foreman's mark that a Board started from a Foreman session inherits is
        # dropped, so testissue holds the issue only when the record's new issues start held.
        return 'cd %s || exit 1; CONVEYOR_FOREMAN= CLAUDE_CODE_SESSION_ID= %s testissue %s %s %s' % (q(record or main), conv, q(args[0]), q(args[1]), q(args[2]))
    if action == 'unlabel':
        # CONVEYOR_UNLABELED: the release dates the owner's release though only the label held the issue (control release).
        labels = ' '.join(f'--remove-label {q(x)}' for x in args[1:])
        return f'cd {q(record or main)} || exit 1; {conv} gh-write issue edit {q(args[0])} {labels} >/dev/null && CONVEYOR_UNLABELED=1 {conv} control release {q(args[0])}'
    if action in ('approve', 'decline'):
        # The line names the record's pack owner: conveyor.sh's conditional() reads any other name as a condition.
        owner = 'o=$(bash %s get owner.name %s)' % (q(main + '/conveyor/lib/pack.sh'), q((record or main) + '/.conveyor/project.json'))
        main = record or main
        n = q(args[0])
        # w: card (a card waiting for the yes) or before (an issue waiting for it before its build).
        gate = ('w=$(%s health | jq -r --argjson n %s \'if any(.waiting[]; .issue == $n) then "card"'
                ' elif any(.before // [] | .[]; .issue == $n) then "before" else empty end\') && [ -n "$w" ]'
                ' || { echo "conveyor: #%s is not waiting for your yes; nothing changed" >&2; exit 2; }' % (conv, n, args[0]))
        said = args[1] if len(args) > 1 else ''

        def then(done):  # a card is retried; an issue waiting before its build has no card: it is said what happened
            return '{ if [ "$w" = before ]; then echo %s; else %s retry %s; fi; }' % (q(done), conv, n)
        if action == 'decline':
            why = ' && %s && %s gh-write issue comment %s --body "Visible change declined: $o, "%s >/dev/null' % (owner, conv, n, q('%s (Board user %s): %s' % (today, user, said))) if said else ''
            # The card is retried before the hold: retry releases an issue it finds held (retry.sh again()), so a hold
            # made first was undone and the declined card was built again.
            held = q(f'conveyor: issue #{args[0]} is held; it is not built until it is released')
            return f'cd {q(main)} || exit 1; {gate}{why} && {{ [ "$w" = before ] || {conv} retry {n}; }} && {conv} control hold {n} >/dev/null && echo {held}'
        # conveyor.sh's conditional() reads "(Board user <name>)" as who said yes, not as a condition.
        rest = ', %s (Board user %s)' % (today, user) + ('; condition: %s' % said if said else '')
        return ('cd %s || exit 1; %s && %s && b=$(gh issue view %s --json body --jq .body)'
                ' && printf \'%%s\\n\\nVisible change approved: %%s%%s\\n\' "$b" "$o" %s'
                ' | %s gh-write issue edit %s --body-file - >/dev/null && %s' % (
                    q(main), gate, owner, n, q(rest), conv, n, then('conveyor: issue #%s is approved before its build; it is picked in its turn' % args[0])))
    return '%s control %s' % (conv, ' '.join(q(x) for x in [action] + args))


def answer_ok(body):
    return (isinstance(body, dict) and set(body) == ANSWER_KEYS
            and isinstance(body['id'], str) and DECISION_ID.match(body['id'])
            and isinstance(body['answer'], str) and 1 <= len(body['answer']) <= 500 and body['answer'].isprintable()
            and isinstance(body['askedAt'], str) and ASKED_AT.match(body['askedAt'])
            and isinstance(body['repo'], str) and REPO.fullmatch(body['repo']))


def log_ruling(question, answer, user):
    """One row in ruling-log.sh's shape, so ruling-id.sh and the cite gate read it like any other, and the Board user
    who answered."""
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    et = now.astimezone(ET)
    row = {'id': 'r-%s-1-%s' % (et.strftime('%Y%m%d-%H%M%S'), secrets.token_hex(3)),
           'utc': now.strftime('%Y-%m-%dT%H:%M:%SZ'), 'et': et.strftime('%Y-%m-%d %H:%M:%S %Z'),
           'session': None, 'cwd': None, 'source': 'dashboard', 'question': question, 'answer': answer,
           'annotations': None, 'pick': 'dashboard', 'user': user}
    with open(RULINGS, 'a') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps(row) + '\n')
    return row['id']


def unsent_path(decision_id):
    return os.path.join(UNSENT, decision_id + '.json')


def read_unsent(decision_id):
    try:
        with open(unsent_path(decision_id)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def drop_unsent(decision_id):
    try:
        os.remove(unsent_path(decision_id))
    except OSError:
        pass


def run_script(args, timeout, env=None):
    """subprocess.run for this server's scripts, in a process group of their own: a timeout kills the whole group, so
    no child (a ledger write) carries on after the page has been answered."""
    with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True, env=env) as p:
        try:
            out, err = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
            raise
    return subprocess.CompletedProcess(args, p.returncode, out, err)
