#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""dashboard_server.py <port> <directory> -- the Conveyor dashboard's page server.

It serves the folder dashboard.sh --loop writes (the page and its data.js), every file `no-cache`, so a browser
revalidates the page's code instead of guessing it is fresh: each file has an ETag from its stat, and a request that
names it in If-None-Match is a 304, so the page polls data.js and alive.js at the same address. Scripts and the
stylesheet go gzip-compressed to a browser that accepts it, and a connection is kept (HTTP/1.1) for the next file. Everything is served over HTTPS
behind a login (the owner's ruling): the only public routes are PUBLIC below.
The page keeps its layout in the browser. A logged-in caller can do these things and nothing else: send the Board's
Time setting through `POST /time` (time.json, the one file written in the served folder, for the /units pane); answer one open decision through `POST /answer`, restart the collector through
`POST /restart`, and steer the Conveyor loop from the Board through `POST /control`: one action of
`conveyor.sh control`, or the yes, the no or the retry of a card, run on the host conveyor/host.json names (here on one
machine: conveyor_host()), on the
record of it the request names (`POST /machine` pauses or resumes the whole machine instead,
and names no record); and manage
users (below). Every write is taken from the page's own address only (own_page), and each names the user who made it
(the ruling row, the approval or decline line, the server's log line). An answer is recorded in the
decisions ledger and the ruling log and sent to no pane. A dashboard-unsent/<id>.json an earlier version left beside
the ruling log is cleared when the page posts that answer again.

`GET /events` is the page's live feed, behind the login like every other route (a caller with none gets 401):
server-sent events. It opens with `snapshot` (the whole of data.js, when there is one), then each time data.js
changes sends one `panel` event per panel whose part changed ({id, part, updatedAt}) and `updated` ({updatedAt}) when
none did; a comment line every PING seconds keeps it open, and a login that has ended closes it. data.js is looked at
every 0.2 s by one thread for every client. At most MAX_FOLLOWERS are open at once (503 past that); the page falls
back to reading data.js every 15 s while it has none.
`GET /history`, behind the login too, gives the older entries data.js no longer carries (dashboard.sh --history):
the page asks for it when its Landed, Metrics, Cost or Declined panel is drawn, at most once a minute.
`GET /work`, behind the login too, gives what keeps the Conveyor host busy now (dashboard.sh --work): the Health
panel asks for it when the owner opens Work now or reads it again.
`GET /older?repo=<repo>&file=<test file>`, behind the login too, gives the older runs and test edits of one test file
that data.js no longer carries (dashboard.sh --older): the Tests page asks for it when that file's Timeline is opened.
`GET /donewhen?repo=<repo>&card=<card id>`, behind the login too, gives a card's last Done-when check item by item,
which data.js does not carry (dashboard.sh --donewhen): the Board asks for it when that card's Done-when line is opened.
`GET /shot?repo=<repo>&card=<card>&file=<file>`, behind the login too, gives one screenshot that a card waiting for the
owner's yes kept (dashboard.sh --shot): Needs you shows it beside the card's Approve.
`GET /excerpts?repo=<repo>&card=<card id>`, behind the login too, gives the lines a card's review findings cite, as each
review kept them from the tree it read (dashboard.sh --excerpts): the Board asks for it when a finding's place is opened.
`GET /bench?repo=<repo>[&run=<run id>]`, behind the login too, gives the Benchmarks tab's history of the SWE-bench
runs, or one run's tasks by arm, which data.js does not carry (dashboard.sh --bench): the tab asks for it when shown.

The login: users in dashboard-auth.json beside the ruling log (env CONVEYOR_DASHBOARD_AUTH), each with a name, a
role (admin or member), an scrypt hash, when it was created and last logged in, its MFA state and its trusted
devices; and the self-signed certificate in dashboard-tls/ beside it. A member uses the Board and manages only their
own password, MFA and devices (`/me`); an admin also manages every user (`/users`, 403 for a member). A new user, or
one whose password an admin resets, gets a one-time setup link (24 h) to set their own password, so no password is
shown or sent. Each user-management action is a line in dashboard-audit.jsonl beside the store (who, what, whom,
when; never a secret). The first user is admin; the last user, and the last admin, cannot be removed, nor the last
admin made a member.
"No login on this device" (the store's noLoginHere; no value reads as on, an admin sets it at /users): a request from
the machine the Board runs on (a loopback peer, from the socket, and a Host of localhost or a loopback address on this
port) needs no login and acts as an admin named "this device" (LOCAL), which has no account of its own at /me.
The login page is login.html of the served folder, with the Board's app.css, icon.svg and its login.js: those
three are served without a login, as the page is. MFA is each user's choice, never required: TOTP per RFC 6238
(SHA-1, 6 digits, 30 s steps), which Google Authenticator and every other authenticator app read; the codes are
pyotp's and the enrolment QR segno's, from the Board's own virtualenv (requirements.txt). A user turns it on from
their account (`/me` mfa-setup, the QR at `GET /me/qr`, then mfa-on with one valid code), and gets 10 one-time
recovery codes, shown once; only their sha256 is kept. Their secret is kept encrypted (Fernet) with the key file
dashboard-mfa.key beside the store, mode 0600, and is never logged, nor shown once MFA is on. A login with MFA on is
the password, then the code (POST /login {code}, within MFA_TTL): the code of this step or the one either side,
never one already taken (each step is used once), or a recovery code, once. A wrong code counts toward the lockout as
a wrong password does. A trusted device skips both steps until it expires. Each device keeps when it was last used
(`used`, written at most once every DEVICE_USED_EVERY seconds), which the account page lists.
Command line, run by the owner with the Board's virtualenv's python3 (dashboard.sh's BOARD_PY), for the first user and
for recovery:
  dashboard_server.py make-cert [--force]             the certificate, once (825 days); again when its key does not name its curve
  dashboard_server.py add-user <user> [--admin]       a user and their password (asked twice)
  dashboard_server.py set-role <user> admin|member    a user's role; ends their sessions
  dashboard_server.py set-password <user>             the password (asked twice); ends their sessions, keeps devices
  dashboard_server.py remove-user <user>              a user, their sessions and devices
  dashboard_server.py mfa-off <user>                  turn off a user's MFA
  dashboard_server.py devices [<user>]                trusted devices: id, label, created, user
  dashboard_server.py revoke <id>|all                 end a device (`all`: every device and every session)
Sessions live in memory (a restart logs them out); a trusted device lasts a year and survives a restart.
"""
import base64
import binascii
import datetime
import fcntl
import functools
import email.utils
import getpass
import gzip
import hashlib
import hmac
import http.server
import io
import ipaddress
import json
import math
import os
import re
import secrets
import shlex
import signal
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.parse
import zoneinfo

import pyotp
import segno
from cryptography.fernet import Fernet

HERE = os.path.dirname(os.path.abspath(__file__))
# An answer is {id, answer, askedAt, repo}, each checked before decision.sh sees it; repo is the host file's record
# whose ledger holds the decision.
MAX_ANSWER_BODY = 4096
MAX_TIME_BODY = 64     # POST /time: {"time": "24-hour"}
RESTART_COOLDOWN = 60  # seconds between restarts; the stamp is a file because the restart kills this server
HISTORY_TTL = 60       # GET /history serves dashboard.sh's copy while it is this young, with no process (its HISTORY_TTL)
HISTORY_LIMIT = 90     # GET /history: dashboard.sh --history's one ssh command (its SSH_LIMIT, 60 s) and the build
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
# or depends (the Board's "Depends on…": `conveyor.sh control depends`, which writes the issue's Depends on: line on GitHub),
# or card (a card's Settings: `conveyor.sh control card`, one issue's own builder, reviewer or judge; and its Pick for
# me, `control card <issue> pick`, whose answer is the judge's settings, changing nothing),
# or full-test (the Rules tab's Run full test suite, Push landed and Push anyway: `conveyor.sh full-test [push | anyway <run id>]`),
# or push-now (the Control tab's Push now: `conveyor.sh push-now`, what landed pushed with no full test run),
# or merge-pr (the Control tab's Merge: `conveyor.sh pr merge`, the open pull request of Land as pr merged now),
# or release-run (the Release panel's buttons and Stop: `conveyor.sh release-run [prep] <version> | release-run stop`,
# and Release anyway: `release-run anyway <version> --by <Board user>`),
# or test-settings (the Tests page's limits, and one file's "slow on purpose" mark: `conveyor.sh test-settings`),
# or standing (the Rules tab's Done without asking: one standing kind of routine yes on or off, `conveyor.sh auto standing`),
# or prices (the Rules tab's Model prices: one model's price set or cleared, a model added or removed, its display name
# or an alias: `conveyor.sh prices`),
# or testmap (the Tests page's Build the test map and its Stop: `conveyor.sh testmap build | stop`; an admin's alone),
# or bench (the Benchmarks tab: Start, Stop, List versions, an arm's preflight and Compare: `conveyor.sh bench swe <n>
# [--solo | [--arm <arm>]... [--engine <version>]] | stop | versions | arms check <arm>... | diff <A> <B> [--json]`; an
# admin's alone),
# or the Tests page's actions: testaction (`conveyor.sh testaction`: judge, explain or run one file, stop one), tests
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
KIND = re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]{0,39}')  # a finding kind the judge always accepts, as conveyor.sh's control takes it
CARD_SEATS = frozenset({'builder', 'reviewer', 'judge'})  # the seats one issue keeps of its own (`conveyor.sh control card`)
KINDS_MAX = 20
# The standing kinds of routine yes, as conveyor.sh's auto standing takes them (conveyor/lib/standing.sh).
STANDING = frozenset({'asked-fix', 'review-followup', 'release-check', 'fixed-block'})
# An area rule is the pack's area prefix and a name: any label here; conveyor.sh checks the prefix.
# The rule Split large issues (split) takes off, shadow or on.
RULE = re.compile(r'split=(off|shadow|on)|(P[0-3]|followups|(?!P[0-9]+=)[A-Za-z0-9][A-Za-z0-9._:/-]{0,79})=(on|off)')
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
# every other action: 30 s. start outlasts conveyor.sh's 60 s `timeout 60 gh issue list` (control start), so the
# panel gets the record and not a 504 while GitHub is slow; raise it with that timeout.
DECLINED_ID = re.compile(r'd[0-9a-f]{12}')  # a line of the declined list, as conveyor.sh's declined() names it
# depends reads the open issues and writes the issue's body, each through gh (the write under gh-write's 60 s timeout).
CONTROL_TIMEOUT = {'approve': 120, 'decline': 120, 'retry': 60, 'unblock': 60, 'close': 60,'start': 90, 'build': 60, 'depends': 120,
                   'testaction': 60, 'testmap': 60, 'test-close': 60, 'test-issue': 60,  # testaction and testmap stop wait up to 40 s for the end
                   'bench': 600,  # bench diff makes one model call a flipped task; its stop waits up to 30 s for the end
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

    def look(self):
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


def fresh_history(directory):
    """dashboard.sh --history's copy, cache/history.json in the served folder (its OUT), as bytes while it is under
    HISTORY_TTL seconds old and a JSON object, the copy that script would print; else None, and the script is run."""
    path = os.path.join(directory, 'cache', 'history.json')
    try:
        if time.time() - os.stat(path).st_mtime >= HISTORY_TTL:
            return None
        with open(path, 'rb') as f:
            body = f.read()
        return body if isinstance(json.loads(body), dict) else None
    except (OSError, ValueError):
        return None


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
    if a in ('hold', 'release', 'unpin'):
        return issues(1, 50)
    if a == 'order':
        return issues(0, 500)
    if a == 'rules':
        return 1 <= n <= 10 and all(RULE.fullmatch(x) for x in v)
    if a == 'judge' and v in (['on'], ['off']):  # the review's judge, on or off
        return True
    if a == 'judge' and n and v[0] == 'always':  # the finding kinds it always accepts, whole; none clears them
        return n <= 1 + KINDS_MAX and all(KIND.fullmatch(x) for x in v[1:])
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
    if a in ('dep-guard', 'push-check'):  # the dependency guard; the run before a push
        return v in (['on'], ['off'])
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
        # Release anyway over release-prep's red suite (anyway, the version) and Stop (stop)
        return (n == 1 and (v[0] == 'stop' or VERSION.fullmatch(v[0]) is not None)) or (n == 2 and v[0] in ('prep', 'anyway') and VERSION.fullmatch(v[1]) is not None)
    if a == 'test-settings':  # the Tests page: a test limit of the pack, or one file's mark
        return test_settings_ok(v)
    if a == 'standing':  # the Rules tab: one standing kind of routine yes, on or off
        return n == 2 and v[0] in STANDING and v[1] in ('on', 'off')
    if a == 'prices':  # the Rules tab's Model prices: one model's price, added model, display name or alias
        return n >= 2 and MODEL.fullmatch(v[1]) is not None and (
            (n in (5, 6) and v[0] == 'set' and all(PRICE.fullmatch(x) for x in v[2:]))
            or (n == 2 and v[0] in ('clear', 'remove'))
            or (n in (7, 8) and v[0] == 'add' and v[2] in PROVIDERS and NAME.fullmatch(v[3]) is not None and all(PRICE.fullmatch(x) for x in v[4:]))
            or (n in (2, 3) and v[0] == 'name' and all(NAME.fullmatch(x) for x in v[2:]))
            or (n == 4 and v[0] == 'alias' and v[2] in ('add', 'remove') and MODEL.fullmatch(v[3]) is not None))
    if a == 'testaction':  # the Tests page: judge, explain or run one test file or a list of them, or stop one action by its id
        return (2 <= n <= 1 + TEST_FILES_MAX and v[0] in ('judge', 'explain', 'run') and all(TEST_FILE.fullmatch(x) for x in v[1:])) \
            or (n == 2 and v[0] == 'stop' and RUN_ID.fullmatch(v[1]) is not None)
    if a == 'testmap':  # the Tests page's Build the test map, or its Stop
        return v in (['build'], ['stop'])
    if a == 'bench':  # the Benchmarks tab: Start (n, then --solo, or arms and a version), Stop, List versions, an arm's preflight, Compare (two versions or results keys)
        if v in (['stop'], ['versions']):
            return True
        if v[:1] == ['diff']:
            return n in (3, 4) and all(BENCH_SIDE.fullmatch(x) for x in v[1:3]) and v[3:] in ([], ['--json'])
        if v[:2] == ['arms', 'check']:
            return 3 <= n <= 2 + BENCH_ARMS_MAX and all(BENCH_ARM.fullmatch(x) for x in v[2:])
        if not (n >= 2 and v[0] == 'run' and BENCH_N.fullmatch(v[1]) is not None and int(v[1]) <= 500):
            return False
        rest, arms = v[2:], 0
        if rest == ['--solo']:
            return True
        while rest[:1] == ['--arm'] and len(rest) >= 2 and BENCH_ARM.fullmatch(rest[1]) is not None:
            rest, arms = rest[2:], arms + 1
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
    if a == 'test-issue':  # File an issue about a test file, or one about each of a list: the file, the title, then the body the owner read and edited
        return n % 3 == 0 and 3 <= n <= 3 * TEST_FILES_MAX and all(
            TEST_FILE.fullmatch(f) is not None and said_ok(t) and len(t) <= 200 and 1 <= len(b.strip()) and len(b) <= TEST_ISSUE_BODY
            and all(line.isprintable() for line in b.split('\n')) for f, t, b in zip(v[0::3], v[1::3], v[2::3]))
    return False


def test_files(action, args):
    """A Tests page action on a list of files (testaction judge, explain or run, test-issue), as (file, the arguments of
    the action on that file alone) for each: control() runs each on its own, as the action on one file, and answers
    each on its own. None for any other action, and for one on a single file, answered as before."""
    if action == 'testaction' and args[0] != 'stop':
        each = [(f, [args[0], f]) for f in args[1:]]
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
# A price as typed, one word: `conveyor.sh prices set` checks it is $ per million tokens and says why it is not, so the
# Rules tab shows the refusal (a negative or a word) in the engine's own words.
PRICE = re.compile(r'\S{1,40}')
# A model's display name (`conveyor.sh prices name` and add): 1 to 60 characters with no control character; and the
# group an added model shows in.
NAME = re.compile(r'[^\x00-\x1f\x7f]{1,60}')
PROVIDERS = frozenset({'claude', 'openai', 'opencode', 'other'})


def test_settings_ok(v):
    """Whether args are one `conveyor.sh test-settings` command: slow-issues true|false, slow-mark <file> <reason: one
    line>, slow-mark-clear <file> or cpu-time <file> (Record CPU time: the pack's test command changed, an admin's
    alone)."""
    n, w = len(v), v[0] if v else None
    if n == 2 and w == 'slow-issues':
        return v[1] in ('true', 'false')
    if n == 3 and w == 'slow-mark':
        return TEST_FILE.fullmatch(v[1]) is not None and said_ok(v[2])
    if n == 2 and w in ('slow-mark-clear', 'cpu-time'):
        return TEST_FILE.fullmatch(v[1]) is not None
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


def host_file():
    """conveyor/host.json as dashboard.sh reads it: this machine's host file when there is one, else the committed one
    of this machine's checkout (board_main()). ValueError when it does not read."""
    host_file = os.path.join(os.environ.get('XDG_CONFIG_HOME') or os.path.expanduser('~/.config'), 'conveyor', 'host.json')
    try:
        # This machine's host file when there is one (dashboard.sh's conveyor() rule), else main's conveyor/host.json.
        with open(host_file if os.path.exists(host_file) else os.path.join(board_main(), 'conveyor', 'host.json')) as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise ValueError('conveyor/host.json is missing or not understood') from e


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
    dismissed by the Board user, so they leave the Declined panel (conveyor.sh declined dismiss). record is the checkout of the record the action
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
        # leaves the records as they are, and the closed issue leaves the snapshot's list of open held follow-ups.
        # A main-red fix card has no issue to close: it is shut alone, by its card id.
        if REDCARD.fullmatch(args[0]):
            return '%s shut %s' % (conv, q(args[0]))
        return 'cd %s || exit 1; %s gh-write issue close %s --comment %s >/dev/null && %s shut %s' % (
            q(record or main), conv, q(args[0]), q("Closed from the Board's Needs you list."), conv, q(args[0]))
    if action == 'build':
        return '%s declined build %s' % (conv, q(args[0]))
    if action == 'dismiss':
        return '%s declined dismiss --by %s %s' % (conv, q('Board user %s' % user), ' '.join(q(x) for x in args))
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
    if action == 'release-run':
        # Release: the owner's yes to release-prep, then release, which run on the host after the answer; prep: release-prep
        # alone (Draft notes, Run suite); or Stop. A release over a red suite (anyway) is logged under the Board user who
        # confirmed it.
        return '%s release-run %s%s' % (conv, ' '.join(q(x) for x in args), ' --by %s' % q('Board user %s' % user) if args[:1] == ['anyway'] else '')
    if action in ('test-settings', 'prices'):
        # The record's pack (.conveyor/project.json of its main), changed by the engine's own command, which checks it.
        return '%s %s %s' % (conv, action, ' '.join(q(x) for x in args))
    if action == 'standing':
        # The record's pack's auto.standing: one kind on or off (conveyor.sh auto standing, which checks it).
        return '%s auto standing %s %s' % (conv, q(args[0]), q(args[1]))
    if action == 'bench':
        if args[0] == 'run' or args[:2] == ['arms', 'check']:
            # A run takes hours, and an arm's preflight minutes: it starts on the host and goes on after the answer. One
            # the engine refuses at once (a run already going, the usage guard reached, a version it cannot take)
            # answers its refusal on stderr, the stream the handler reads when a script fails; one that ends well at
            # once (all its results saved before) answers its summary on stdout, the stream the handler reads when a
            # script succeeds.
            what, rest = ('the SWE-bench run', args[1:]) if args[0] == 'run' else ("the arms' preflights", args)
            return ('l=$(mktemp) || exit 1; %s bench swe %s > "$l" 2>&1 < /dev/null & p=$!; sleep 3; '
                    'if kill -0 "$p" 2>/dev/null; then rm -f "$l"; echo "conveyor: %s started"; '
                    'else wait "$p"; r=$?; if [ "$r" = 0 ]; then cat "$l"; else cat "$l" >&2; fi; rm -f "$l"; exit "$r"; fi') % (conv, ' '.join(q(x) for x in rest), what)
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
    if action == 'test-issue':
        # The engine files it (the pack's type and last priority) and keeps it for the file's row: Close its issue as done.
        return 'cd %s || exit 1; %s testissue %s %s %s' % (q(record or main), conv, q(args[0]), q(args[1]), q(args[2]))
    if action == 'unlabel':
        return 'cd %s || exit 1; %s gh-write issue edit %s %s >/dev/null && %s control release %s' % (
            q(record or main), conv, q(args[0]), ' '.join('--remove-label %s' % q(x) for x in args[1:]), conv, q(args[0]))
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
            return 'cd %s || exit 1; %s%s && %s control hold %s >/dev/null && %s' % (
                q(main), gate, why, conv, n, then('conveyor: issue #%s is held; it is not built until it is released' % args[0]))
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


def sha(token):
    return hashlib.sha256(token.encode()).hexdigest()


def load_store():
    """The store as the file holds it now, a new dict each call ({} for one of another shape); OSError when the file
    cannot be read."""
    with open(AUTH) as f:
        try:
            store = json.load(f)
        except ValueError:
            return {}
    return store if isinstance(store, dict) else {}


def parse_store():
    """load_store, with {} for a store that cannot be read."""
    try:
        return load_store()
    except OSError:
        return {}


# The store as last parsed, kept in memory: ((mtime_ns, size, ino) of the file, the store). change_store writes a new
# file and renames it over the old one, so each change has a new inode and is parsed again on the next read. A read
# that fails is never kept: a mode change leaves the key as it was, and the next request must try the file again.
STORE = [None, None]
STORE_LOCK = threading.Lock()


def read_store():
    """The store, parsed again only when its file changed. The one dict is shared by every request: read it, never
    change it (change_store parses its own copy)."""
    try:
        st = os.stat(AUTH)
        key = (st.st_mtime_ns, st.st_size, st.st_ino)
    except OSError:
        return {}
    with STORE_LOCK:
        if STORE[0] != key:
            try:
                STORE[:] = [key, load_store()]
            except OSError:
                STORE[:] = [None, None]
                return {}
        return STORE[1]


def change_store(fn):
    """Every read-modify-write of the store, here and in the CLI, runs under one flock and is written temp-then-rename,
    mode 0600; returns what fn(store) returns."""
    os.makedirs(os.path.dirname(AUTH), mode=0o700, exist_ok=True)
    with os.fdopen(os.open(AUTH + '.lock', os.O_CREAT | os.O_RDWR, 0o600)) as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        store = parse_store()
        if not isinstance(store.get('users'), dict):
            store['users'] = {}
        if not isinstance(store.get('setups'), dict):
            store['setups'] = {}
        out = fn(store)
        tmp = '%s.%d.tmp' % (AUTH, os.getpid())
        with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as f:
            json.dump(store, f)
        os.replace(tmp, AUTH)
    return out


def stamp_time(text):
    """The seconds of a stamp(), or None for anything else."""
    try:
        return datetime.datetime.strptime(text, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()
    except (ValueError, TypeError):
        return None


def device_ok(device, now):
    """A trusted device is good for DEVICE_TTL from its creation, however long its cookie is kept (R04)."""
    made = stamp_time(device.get('created'))
    return made is not None and now < made + DEVICE_TTL


def device_used(name, device, now):
    """Records now as the last use of name's trusted device, unless one was recorded under DEVICE_USED_EVERY ago."""
    def touch(store):
        d = devices_of(users_of(store).get(name, {})).get(device)
        if isinstance(d, dict) and now - (stamp_time(d.get('used')) or 0) >= DEVICE_USED_EVERY:
            d['used'] = stamp(now)
    change_store(touch)


def users_of(store):
    """{name: user} of the store, users of another shape left out."""
    users = store.get('users')
    return {k: v for k, v in users.items() if isinstance(v, dict)} if isinstance(users, dict) else {}


def devices_of(user):
    d = user.get('devices')
    return d if isinstance(d, dict) else {}


def stamp(t=None):
    return datetime.datetime.fromtimestamp(time.time() if t is None else t, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def password_ok(store, user, password):
    """Always one scrypt, so a wrong user (or one with no password yet) costs what a wrong password does."""
    u = users_of(store).get(user) or {}
    try:
        salt, want = bytes.fromhex(u['salt']), bytes.fromhex(u['hash'])
        params = {k: u[k] for k in SCRYPT}
        known = True
    except (KeyError, ValueError, TypeError):
        salt, want, params, known = b'\0' * 16, b'\0' * 32, SCRYPT, False
    try:
        got = hashlib.scrypt(password.encode(), salt=salt, dklen=len(want), **params)
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(got, want) and known


def bump(store, user):
    """A new epoch for the user, so their sessions end. Every epoch comes from one count for the whole store, never
    given twice: a later user of a removed user's name never matches the removed user's sessions."""
    store['epoch'] = store.get('epoch', 0) + 1
    user['epoch'] = store['epoch']


def password_problem(pw, user):
    """Why user's new password is refused, or None. It must fit the /login body the login page sends for that user,
    untrusted with no label, as JSON.stringify encodes it (compact, UTF-8)."""
    if len(pw) < 8:
        return 'the password must be at least 8 characters'
    body = {'user': user, 'password': pw, 'trust': False, 'label': ''}
    if len(json.dumps(body, ensure_ascii=False, separators=(',', ':')).encode()) > MAX_LOGIN_BODY:
        return 'the password is too long to log in with'
    return None


def set_hash(store, user, password):
    """The password's scrypt hash (today's parameters); the user's epoch moves, so their sessions end."""
    salt = os.urandom(16)
    user.update(salt=salt.hex(), hash=hashlib.scrypt(password.encode(), salt=salt, dklen=32, **SCRYPT).hex(), **SCRYPT)
    bump(store, user)


def mfa_key(create=False):
    """The Fernet that keeps the TOTP secrets, from its key file beside the store (mode 0600). create (inside
    change_store, so two setups cannot both make one) makes the file the first time."""
    try:
        with open(MFA_KEY, 'rb') as f:
            return Fernet(f.read().strip())
    except FileNotFoundError:
        if not create:
            raise
    key = Fernet.generate_key()
    with os.fdopen(os.open(MFA_KEY, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as f:
        f.write(key)
    return Fernet(key)


def totp(secret):
    """RFC 6238 as authenticator apps read it: SHA-1, 6 digits, 30 s steps."""
    return pyotp.TOTP(secret, digits=6, digest=hashlib.sha1, interval=30)


def totp_step(secret, code, now, after):
    """The step code is the TOTP code of (now's, or one either side), if that step is later than after, else None.
    Compared as bytes: compare_digest refuses a str that is not ASCII, and any typed code must be refused, not raise; a
    code that is not ASCII (a lone surrogate, which encode() cannot take) is never right."""
    if not code.isascii():
        return None
    t = totp(secret)
    step = t.timecode(datetime.datetime.fromtimestamp(now, datetime.timezone.utc))
    for s in (step - 1, step, step + 1):
        if s > after and hmac.compare_digest(t.generate_otp(s).encode(), code.encode()):
            return s
    return None


def recovery_form(code):
    """A recovery code as it is hashed: as shown, or typed without its dashes or with spaces."""
    return code.replace('-', '').replace(' ', '')


def mfa_passes(u, code, now):
    """Whether code is u's second step: a TOTP code no step of which was taken before (it is then the last taken), or
    one of u's recovery codes (it is then used up). Changes u: call it inside change_store."""
    secret = u.get('totp')
    step = totp_step(mfa_key().decrypt(secret.encode()).decode(), code, now, u.get('totpStep', -1)) if secret else None
    if step is not None:
        u['totpStep'] = step
        return True
    h = sha(recovery_form(code))
    if h in u.get('recovery', []):
        u['recovery'].remove(h)
        return True
    return False


def mfa_setup(u, name):
    """A new secret for u, kept (encrypted) as pending until mfa_on; it replaces any earlier pending one. Returns it, the
    one time it is shown."""
    if u.get('mfa'):
        raise Refused('authenticator codes are already on: turn them off first')
    secret = pyotp.random_base32()
    u['totpPending'] = mfa_key(create=True).encrypt(secret.encode()).decode()
    return {'secret': secret, 'uri': totp(secret).provisioning_uri(name=name, issuer_name=MFA_ISSUER)}


def mfa_on(u, code, now):
    """MFA on for u once code is a valid code of the pending secret; returns the recovery codes, the one time they are
    shown. Only their sha256 is kept."""
    if u.get('mfa') or not u.get('totpPending'):
        raise Refused('no authenticator setup is under way: start it again')
    step = totp_step(mfa_key().decrypt(u['totpPending'].encode()).decode(), code, now, -1)
    if step is None:
        raise Refused('that code is not right: check the clock on your phone, then enter the code it shows now', 403)
    # 16 digits each (53 bits), so the code field's number pad types them too.
    codes = ['-'.join(''.join(secrets.choice('0123456789') for _ in range(4)) for _ in range(4)) for _ in range(RECOVERY_CODES)]
    u.update(mfa=True, totp=u.pop('totpPending'), totpStep=step, recovery=[sha(recovery_form(c)) for c in codes])
    return codes


class Refused(Exception):
    """A user-management action the rules refuse; its message is the reply, with its HTTP status (409 unless given)."""
    def __init__(self, text, code=409):
        super().__init__(text)
        self.code = code


def admins(store):
    return [n for n, u in users_of(store).items() if u.get('role') == 'admin']


def no_login_here(store):
    """The "No login on this device" setting: on unless the store says false."""
    return store.get(NO_LOGIN_HERE) is not False


def role_of(store, name):
    """The role a logged-in name acts with: LOCAL is an admin; a user, their stored role."""
    return 'admin' if name == LOCAL else users_of(store).get(name, {}).get('role')


def need(store, name):
    u = users_of(store).get(name)
    if u is None:
        raise Refused('no such user: %s' % name)
    return u


def drop_setups(store, name=None):
    """The setup links left: none of the user's (name), none expired."""
    now = time.time()
    store['setups'] = {k: v for k, v in store['setups'].items() if isinstance(v, dict) and v.get('user') != name
                       and isinstance(v.get('exp'), (int, float)) and v['exp'] > now}


def setup_link(store, name):
    """A new one-time setup token for the user, good for SETUP_TTL; it replaces any earlier one. Only its sha256 is kept."""
    token = secrets.token_urlsafe(32)
    drop_setups(store, name)
    store['setups'][sha(token)] = {'user': name, 'exp': time.time() + SETUP_TTL}
    return token


def user_action(store, action, name, role=None, device=None):
    """One user-management action on the store (inside change_store), shared by the Board and the command line.
    add and reset return the new setup token. Refused when the rules forbid it: the first user is admin, the last user
    and the last admin stay, the last admin stays admin. A role change ends the user's sessions (their epoch moves)."""
    users = store['users']
    if action == 'add':
        if not USER.fullmatch(name):
            raise Refused('a user name is letters, digits, . _ -; up to 40')
        if name in users:
            raise Refused('%s is already a user' % name)
        if role not in ROLES:
            raise Refused('a role is admin or member')
        users[name] = {'role': 'admin' if not users_of(store) else role, 'created': stamp(), 'lastLogin': None, 'mfa': False,
                       'devices': {}}
        bump(store, users[name])
        return setup_link(store, name)
    u = need(store, name)
    if action == 'role':
        if role not in ROLES:
            raise Refused('a role is admin or member')
        if role == 'member' and admins(store) == [name]:
            raise Refused('%s is the last admin: make another user admin first' % name)
        if u.get('role') != role:
            u['role'] = role
            bump(store, u)
    elif action == 'reset':
        for k in ('salt', 'hash'):
            u.pop(k, None)
        bump(store, u)
        return setup_link(store, name)
    elif action == 'mfa-off':  # its secret and recovery codes go with it
        u['mfa'] = False
        for k in ('totp', 'totpPending', 'totpStep', 'recovery'):
            u.pop(k, None)
    elif action == 'revoke':
        if device == 'all':
            u['devices'] = {}
        elif device in devices_of(u):
            del u['devices'][device]
        else:
            raise Refused('%s has no device %s' % (name, device))
    elif action == 'remove':
        if len(users_of(store)) == 1:
            raise Refused('%s is the last user and cannot be removed' % name)
        if admins(store) == [name]:
            raise Refused('%s is the last admin and cannot be removed: make another user admin first' % name)
        del users[name]
        drop_setups(store, name)
    else:
        raise Refused('no such action: %s' % action)
    return None


def audit(by, action, user, **more):
    """One line per user-management action, beside the store: who, what, whom, when. Never a password, hash or token."""
    row = dict({'time': stamp(), 'by': by, 'action': action, 'user': user}, **more)
    with os.fdopen(os.open(AUDIT, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600), 'a') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps(row) + '\n')


def cookie(name, value, ttl):
    # The device cookie is Lax, so a top-level GET from another site or app (a link in a message, a home-screen open)
    # carries it and a trusted device gets in. Every write is a POST that own_page checks, so Lax opens no cross-site write.
    return '%s=%s; HttpOnly; Secure; SameSite=%s; Path=/; max-age=%d' % (name, value, 'Lax' if name == 'pp_device' else 'Strict', ttl)


def own_cookies(header):
    """The Board's own cookies (pp_session, pp_device, pp_mfa) in a Cookie header: name -> value, the first of each
    name. Split on ';' and '=' rather than read with http.cookies, which drops every cookie in the header when any one
    value is one it rejects (JSON with quotes, a space), and a browser sends the Board every cookie another app on
    the same host set."""
    jar = {}
    for part in header.split(';'):
        name, eq, value = part.partition('=')
        name = name.strip()
        if eq and name in ('pp_session', 'pp_device', 'pp_mfa') and name not in jar:
            jar[name] = value.strip()
    return jar


def ask(prompt):
    return getpass.getpass(prompt) if sys.stdin.isatty() else sys.stdin.readline().rstrip('\n')


# The DER of the OID 1.2.840.10045.3.1.7, the curve prime256v1 (P-256): a certificate whose key names its curve holds it.
P256_OID = bytes.fromhex('06082a8648ce3d030107')


def cert_names_p256(path):
    """True when the certificate at path holds a key that names the curve prime256v1. LibreSSL (macOS's
    /usr/bin/openssl) writes the curve's explicit parameters unless told not to, and curl refuses that certificate."""
    try:
        with open(path) as f:
            return P256_OID in ssl.PEM_cert_to_DER_cert(f.read())
    except (OSError, ValueError):
        return False


def cert_problem():
    """Why the certificate cannot serve the Board, or None when it can: missing, empty, not loadable with its key (the
    server would exit at once on every start), or a key that does not name its curve."""
    if not os.path.exists(CERT):
        return 'is missing'
    if os.path.getsize(CERT) == 0:
        return 'is empty'
    try:
        ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER).load_cert_chain(CERT, KEY)
    except (OSError, ValueError) as e:  # ssl.SSLError is an OSError
        return 'cannot be loaded with its key %s (%s)' % (KEY, e)
    if not cert_names_p256(CERT):
        return 'does not name its curve (prime256v1), so curl cannot check it'
    return None


def cli_make_cert(force):
    # Not an error: dashboard.sh --install runs this every time, and restarts the Board on a certificate made again;
    # dashboard.sh --loop runs it before each start of the server and logs the first line when it makes one.
    if not force:
        why = cert_problem()
        if why is None:
            print('certificate kept: %s (--force makes a new one)' % CERT)
            return
        print('certificate %s %s: making a new one' % (CERT, why))
    host = re.sub(r'[^A-Za-z0-9-]', '', socket.gethostname().split('.')[0]) or 'localhost'
    os.makedirs(TLS, mode=0o700, exist_ok=True)
    old = os.umask(0o077)
    try:
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256',
                        '-pkeyopt', 'ec_param_enc:named_curve', '-nodes', '-days', '825',
                        '-keyout', KEY, '-out', CERT, '-subj', '/CN=%s.local' % host,
                        '-addext', 'subjectAltName=DNS:%s.local,DNS:localhost,IP:127.0.0.1' % host],
                       check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError) as e:
        sys.exit('openssl could not make the certificate: %s' % (getattr(e, 'stderr', None) or e))
    finally:
        os.umask(old)
    print('certificate for %s.local, localhost and 127.0.0.1 in %s (825 days)' % (host, TLS))


def ask_password(name):
    pw = ask('password: ')
    if password_problem(pw, name):
        sys.exit(password_problem(pw, name))
    if ask('again: ') != pw:
        sys.exit('the two passwords differ')
    return pw


def cli_action(action, name, role=None, device=None, password=None):
    """One user action from the command line (the owner: `by` is cli), with its password when it sets one."""
    def act(store):
        user_action(store, action, name, role, device)
        if password is not None:  # the owner sets it here: no setup link
            set_hash(store, need(store, name), password)
            drop_setups(store, name)
        return users_of(store).get(name, {}).get('role')
    try:
        got = change_store(act)
    except Refused as e:
        sys.exit(str(e))
    audit('cli', action, name, **({'role': got} if action in ('add', 'role') else {}), **({'device': device} if device else {}))
    return got


def cli_add_user(name, admin):
    if not USER.fullmatch(name):
        sys.exit('usage: dashboard_server.py add-user <user> [--admin]   (letters, digits, . _ -; up to 40)')
    role = cli_action('add', name, 'admin' if admin else 'member', password=ask_password(name))
    print('%s added (%s)' % (name, role))


def cli_set_password(name):
    pw = ask_password(name)
    # The user's epoch moves, so their sessions end, including ones made from a device; the devices stay (`revoke`).
    # A store with no user yet gets this one as its first, an admin.
    def setpw(store):
        if not users_of(store):
            user_action(store, 'add', name, 'admin')
        set_hash(store, need(store, name), pw)
        drop_setups(store, name)
    try:
        change_store(setpw)
    except Refused as e:
        sys.exit('%s (add-user adds one)' % e)
    audit('cli', 'set-password', name)
    print('password set for %s' % name)


def cli_can_open():
    """Exit 0 when the Board the store the login reads serves can be opened: "No login on this device" is on (this
    machine needs no password), or an admin has a password; `dashboard.sh --install` asks before it restarts the
    server."""
    store = read_store()
    ok = no_login_here(store)
    for name in admins(store):
        u = users_of(store)[name]
        try:
            # The parse and scrypt password_ok runs: a user it rejects whatever the password is has no password at all.
            want = bytes.fromhex(u['hash'])
            hashlib.scrypt(b'', salt=bytes.fromhex(u['salt']), dklen=len(want), **{k: u[k] for k in SCRYPT})
            ok = ok or bool(USER.fullmatch(name))
        except (KeyError, ValueError, TypeError):
            pass
    if not ok:
        sys.exit('"No login on this device" is off and no dashboard admin has a usable password in %s: add one first with dashboard_server.py add-user <user> --admin; the running server is untouched' % AUTH)


def cli_devices(name=None):
    rows = [(i, d, n) for n, u in users_of(read_store()).items() if name in (None, n) for i, d in devices_of(u).items() if isinstance(d, dict)]
    for i, d, n in sorted(rows, key=lambda x: str(x[1].get('created'))):
        print('%s\t%s\t%s\t%s' % (i, d.get('label'), d.get('created'), n))


def cli_revoke(which):
    def revoke(store):
        if which == 'all':  # every device, and every session: each user's epoch moves
            for u in users_of(store).values():
                u['devices'] = {}
                bump(store, u)
            return 'all'
        for n, u in users_of(store).items():
            if which in devices_of(u):
                del u['devices'][which]
                return n
        return None
    who = change_store(revoke)
    if who is None:
        sys.exit('no such device: %s' % which)
    audit('cli', 'revoke', who, device=which)


def start_session(name, epoch, trust, label, now, coded, kept=None):
    """A session for name (under LOGIN), and a trusted device when trust: the Set-Cookie values, or None when the
    user's epoch moved since their login was checked, or MFA is on for them and this login gave no code (coded).
    kept is the browser's pp_device cookie: when it is still a good device of name's, a trusted login keeps that
    device rather than adding another one."""
    token, device = None, None

    def done(s):
        nonlocal token, device
        # A new password, a role change, a revoke-all or the user's removal since the check above means the
        # password checked may be the old one. MFA turned on since then (mfa_on does not move the epoch) means a
        # password-only login that read it off must not finish without a code.
        u = users_of(s).get(name)
        if u is None or u.get('epoch') != epoch or (u.get('mfa') and not coded):
            return None
        u['lastLogin'] = stamp(now)
        if trust:
            have = [i for i, d in devices_of(u).items()
                    if kept and isinstance(d, dict) and d.get('sha') == sha(kept) and device_ok(d, now)]
            if have:
                token, device = kept, have[0]
                u['devices'][device]['used'] = stamp(now)
            else:
                token, device = secrets.token_urlsafe(32), secrets.token_hex(6)
                u.setdefault('devices', {})[device] = {'sha': sha(token), 'label': label or 'device', 'created': stamp(now), 'used': stamp(now)}
        return epoch
    if change_store(done) is None:
        return None
    # A login without trust clears the browser's device cookie: one kept from another user's trusted login
    # would let that user back in once this session ends.
    cookies = [cookie('pp_device', token, DEVICE_TTL) if device else cookie('pp_device', '', 0)]
    session = secrets.token_urlsafe(32)
    for k in [k for k, v in SESSIONS.items() if v['exp'] <= now]:
        del SESSIONS[k]
    SESSIONS[sha(session)] = {'exp': now + SESSION_TTL, 'epoch': epoch, 'device': device, 'user': name}
    return cookies + [cookie('pp_session', session, SESSION_TTL)]


class Handler(http.server.SimpleHTTPRequestHandler):
    timeout = 30  # a client that stalls (or never finishes the TLS handshake) frees its thread
    # A browser runs a module (Belt 3D's three.js, vendor/three/) only with a JavaScript type, whatever the system's
    # own table of types says.
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, '.js': 'text/javascript'}
    # A browser keeps its connection for the page's next file, so the first load is not a TLS handshake a file. Every
    # reply so has a Content-Length; the /events stream, which has none, says Connection: close and closes.
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):  # request lines would flood dashboard.log
        pass

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Vary', 'Accept-Encoding')
        # A POST can be answered before its body is read (a refused write, /restart's body that is never read): the
        # rest of the body must not be read as the next request, so the connection ends with the reply.
        if self.command == 'POST' and not self.close_connection:
            self.send_header('Connection', 'close')
        tag, self.tag = getattr(self, 'tag', None), None
        if tag:
            self.send_header('ETag', tag)
        super().end_headers()

    def file_head(self):
        """A file of the served folder, as SimpleHTTPRequestHandler serves it, with its ETag; a request whose
        If-None-Match names it is a 304. A script or the stylesheet goes gzip-compressed to a browser that accepts it
        (gzipped: its compressed copy, made when the file changed)."""
        path = self.translate_path(self.path)
        if os.path.isdir(path) and urllib.parse.urlsplit(self.path).path.endswith('/'):
            # The folder's index page, as SimpleHTTPRequestHandler picks it (`/` is the Board's index.html): its tag.
            path = next((p for p in (os.path.join(path, i) for i in ('index.html', 'index.htm')) if os.path.isfile(p)), path)
        zipped = path.endswith(GZIP_TYPES) and accepts_gzip(self.headers.get('Accept-Encoding'))
        try:
            st = os.stat(path)
        except OSError:
            return super().send_head()  # gone, or unreadable: its 404 or 403
        if not os.path.isfile(path):
            return super().send_head()
        self.tag = etag(st, zipped)
        if etag_matches(self.headers.get('If-None-Match'), self.tag):
            self.send_response(304)
            self.end_headers()
            return None
        if not zipped:
            return super().send_head()
        try:
            since = self.headers.get('If-Modified-Since')
            if since and 'If-None-Match' not in self.headers:
                try:
                    at = email.utils.parsedate_to_datetime(since)
                    if int(st.st_mtime) <= (at if at.tzinfo else at.replace(tzinfo=datetime.timezone.utc)).timestamp():
                        self.send_response(304)
                        self.end_headers()
                        return None
                except (TypeError, ValueError, IndexError, OverflowError):
                    pass  # a date that does not parse: the whole file, as SimpleHTTPRequestHandler does
            body = gzipped(path, st)
        except OSError:
            self.tag = None
            return super().send_head()  # gone, or unreadable: its 404 or 403
        self.send_response(200)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Content-Encoding', 'gzip')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Last-Modified', self.date_time_string(st.st_mtime))
        self.end_headers()
        return io.BytesIO(body)

    def public(self):
        return (self.command, urllib.parse.urlsplit(self.path).path) in PUBLIC

    def authed(self, store=None):
        """The logged-in user's name, or None. A live session (unexpired, of a user still in the store, made under that
        user's current epoch, and its device, if any, still trusted) or a trusted device cookie that has not outlived
        DEVICE_TTL; with neither, LOCAL for a request from this device (this_device). The store is looked at per request
        (read_store parses it again once its file changed), so a revoke, a new password, a role change, a removed user
        or the setting turned off takes effect on the next
        one; store, as change_store holds it, checks again under its lock. Only a call that reads the store itself
        records a trusted device's use (device_used takes that lock, so a store passed in may be held under it)."""
        touch = store is None
        store = read_store() if store is None else store
        users, now = users_of(store), time.time()

        def used(name, device):
            if touch and now - (stamp_time(devices_of(users[name])[device].get('used')) or 0) >= DEVICE_USED_EVERY:
                device_used(name, device, now)
            return name
        jar = own_cookies(self.headers.get('Cookie', ''))
        if 'pp_session' in jar:
            s = SESSIONS.get(sha(jar['pp_session']))
            u = users.get(s['user']) if s else None
            if u is not None and now < s['exp'] and s['epoch'] == u.get('epoch') and (
                    s['device'] is None or (isinstance(devices_of(u).get(s['device']), dict) and device_ok(devices_of(u)[s['device']], now))):
                return s['user'] if s['device'] is None else used(s['user'], s['device'])
        if 'pp_device' in jar:
            h = sha(jar['pp_device'])
            for name, u in users.items():
                for i, d in devices_of(u).items():
                    if isinstance(d, dict) and d.get('sha') == h and device_ok(d, now):
                        return used(name, i)
        return LOCAL if self.this_device(store) else None

    def this_device(self, store):
        """Whether the request is from the machine the Board runs on, with "No login on this device" on: the
        connection's own peer, from the socket (never a header such as X-Forwarded-For), is a loopback address, and the
        Host is localhost or a loopback address on this server's port, so a name another site points at this machine
        (DNS rebinding) never gets its page in through the owner's browser."""
        if not no_login_here(store):
            return False
        try:
            peer = ipaddress.ip_address(self.client_address[0])
        except ValueError:
            return False
        peer = getattr(peer, 'ipv4_mapped', None) or peer
        name, _, port = self.headers.get('Host', '').rpartition(':')
        name = name[1:-1] if name.startswith('[') and name.endswith(']') else name
        try:
            loopback_host = name == 'localhost' or ipaddress.ip_address(name).is_loopback
        except ValueError:
            loopback_host = False
        return peer.is_loopback and loopback_host and port == str(self.server.server_address[1])

    def send_head(self):
        path = urllib.parse.urlsplit(self.path).path
        if self.public() and path == '/setup':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(SETUP_PAGE)))
            self.end_headers()
            return io.BytesIO(SETUP_PAGE)
        if path == '/login' and self.authed() not in (None, LOCAL):
            # A trusted device or a live session needs no login: the login page sends it on to the Board.
            self.send_response(302)
            self.send_header('Location', '/')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return None
        if self.public():
            self.path = '/login.html'
            return self.file_head()
        if path in LOGIN_FILES:
            return self.file_head()
        if not self.authed():
            self.send_response(302)
            self.send_header('Location', '/login')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return None
        return self.file_head()

    def own_page(self):
        """Whether a write comes from this server's own page. A JSON content type makes a browser ask first (a
        preflight this server never answers), so another site's page cannot send it from the owner's browser; the Origin
        must be this page's; and the Host must be a name no other site can point here (DNS rebinding gives its
        page a matching Origin), on this server's port."""
        host = self.headers.get('Host', '')
        name, _, port = host.rpartition(':')
        name = name[1:-1] if name.startswith('[') and name.endswith(']') else name
        try:
            ipaddress.ip_address(name)
            literal = True
        except ValueError:
            literal = False
        return (self.headers.get('Content-Type') == 'application/json'
                and self.headers.get('Origin') == 'https://' + host
                and port == str(self.server.server_address[1])
                and (literal or name == 'localhost' or re.fullmatch(r'[a-z0-9-]+(\.[a-z0-9-]+)*\.local', name or '') is not None))

    def reply(self, code, text, headers=None):
        body = text.encode()
        self.send_response(code)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def login(self):
        """POST /login {user, password, trust, label}, then, for a user with MFA on, POST /login {code} with the
        pp_mfa cookie the first step set (202). The lockout check, each compare and the failure record happen under
        one lock; no password, code or token reaches a log or a reply body."""
        if not self.own_page():
            return self.send_error(403)
        length = self.headers.get('Content-Length', '')
        if not length.isdigit() or int(length) > MAX_LOGIN_BODY:
            return self.send_error(413)
        try:
            body = json.loads(self.rfile.read(int(length)))
        except ValueError:
            return self.send_error(400)
        if isinstance(body, dict) and set(body) == {'code'}:
            return self.login_code(body['code'])
        label = body.get('label', '') if isinstance(body, dict) else None
        # The device name is optional: the login page sends '' when it is left blank (login_with_no_device_name).
        if not (isinstance(body, dict) and isinstance(body.get('user'), str) and isinstance(body.get('password'), str)
                and isinstance(body.get('trust'), bool) and isinstance(label, str) and len(label) <= 40
                and (label == '' or label.isprintable())):
            return self.send_error(400)
        with LOGIN:
            now = time.time()
            store = read_store()
            if not any(u.get('hash') for u in users_of(store).values()):
                return self.reply(503, NO_PASSWORD)
            if now < LOCKED[0]:
                return self.reply(429, 'too many failed logins: try again in 15 minutes')
            if not password_ok(store, body['user'], body['password']):
                return self.failed('wrong user or password', now)
            name = body['user']
            epoch = store['users'][name].get('epoch')
            if store['users'][name].get('mfa'):
                # The failures are not cleared: a password alone must not reset the count against the code.
                token = secrets.token_urlsafe(32)
                for k in [k for k, v in MFA_PENDING.items() if v['exp'] <= now]:
                    del MFA_PENDING[k]
                MFA_PENDING[sha(token)] = {'user': name, 'epoch': epoch, 'trust': body['trust'], 'label': label, 'exp': now + MFA_TTL}
                return self.reply(202, 'enter the code from your authenticator app', {'Set-Cookie': cookie('pp_mfa', token, MFA_TTL)})
            FAILS.clear()
            cookies = start_session(name, epoch, body['trust'], label, now, False,
                                    own_cookies(self.headers.get('Cookie', '')).get('pp_device'))
        if cookies is None:
            return self.reply(401, 'your login changed: log in again')
        self.logged_in(cookies)

    def failed(self, text, now):
        """A failed password or code: counted toward the lockout (under LOGIN); the reply is 401 text."""
        FAILS[:] = [t for t in FAILS if now - t < LOCK_WINDOW] + [now]
        if len(FAILS) >= LOCK_AFTER:
            LOCKED[0], FAILS[:] = now + LOCK_WINDOW, []
        return self.reply(401, text)

    def login_code(self, code):
        """The code step: the login the pp_mfa cookie names, if it has not expired, ends in a session when code is the
        user's TOTP code or one of their recovery codes (mfa_passes)."""
        if not (isinstance(code, str) and 1 <= len(code) <= 40 and code.isprintable()):
            return self.send_error(400)
        jar = own_cookies(self.headers.get('Cookie', ''))
        key = sha(jar['pp_mfa']) if 'pp_mfa' in jar else None
        with LOGIN:
            now = time.time()
            if now < LOCKED[0]:
                return self.reply(429, 'too many failed logins: try again in 15 minutes')
            p = MFA_PENDING.get(key)
            if p is None or now >= p['exp']:
                MFA_PENDING.pop(key, None)
                return self.reply(401, 'the code step has expired: log in again')

            def check(s):
                u = users_of(s).get(p['user'])
                if u is None or u.get('epoch') != p['epoch']:
                    return None
                return mfa_passes(u, code, now)
            ok = change_store(check)
            if ok is None:
                del MFA_PENDING[key]
                return self.reply(401, 'the password changed: log in again')
            if not ok:
                return self.failed('wrong code', now)
            del MFA_PENDING[key]
            FAILS.clear()
            cookies = start_session(p['user'], p['epoch'], p['trust'], p['label'], now, True, jar.get('pp_device'))
        if cookies is None:
            return self.reply(401, 'the password changed: log in again')
        self.logged_in(cookies + [cookie('pp_mfa', '', 0)])

    def logged_in(self, cookies):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', '2')
        for c in cookies:
            self.send_header('Set-Cookie', c)
        self.end_headers()
        self.wfile.write(b'ok')

    def set_time(self):
        """POST /time {time}: the Board's Time setting (12-hour or 24-hour), as a browser last set it or opened the Board with it.
        Same checks and order as /answer. It is written whole to time.json in the served folder, where the /units
        pane on this machine reads it (hooks/units.tsx readTime): the one file this server writes there."""
        if not self.own_page():
            return self.send_error(403)
        user = self.authed()
        if not user:
            return self.reply(401, 'log in to set the time')
        body = self.json_body(MAX_TIME_BODY)
        if body is None:
            return None
        if set(body) != {'time'} or body['time'] not in ('12-hour', '24-hour'):
            return self.send_error(400)
        tmp = os.path.join(self.directory, '.time.json.%d' % threading.get_ident())
        try:
            with open(tmp, 'w') as f:
                json.dump({'time': body['time']}, f)
            os.chmod(tmp, 0o644)
            os.replace(tmp, os.path.join(self.directory, 'time.json'))
        except OSError as e:
            try:
                os.remove(tmp)  # each thread names its own: one left behind would never be replaced
            except OSError:
                pass
            return self.reply(500, 'the Time could not be kept: %s' % e.strerror)
        print('dashboard: Time set to %s by %s from %s' % (body['time'], user, self.client_address[0]), file=sys.stderr, flush=True)
        self.reply(200, 'kept')

    def restart_collector(self):
        """POST /restart: restarts the collector job through dashboard.sh --restart, which kills this server
        too. Same checks and order as /answer; no body is read and the command is fixed. The reply goes out before
        the command, so each failure of it is logged here, where the page cannot show it."""
        if not self.own_page():
            return self.send_error(403)
        user = self.authed()
        if not user:
            return self.reply(401, 'log in to restart')
        stamp = os.path.join(os.path.dirname(AUTH), 'dashboard-restart-at')
        try:
            if time.time() - os.stat(stamp).st_mtime < RESTART_COOLDOWN:
                return self.reply(429, 'restarted under a minute ago')
        except OSError:
            pass  # no stamp yet
        try:
            open(stamp, 'w').close()
        except OSError:
            return self.reply(500, 'could not write the restart cooldown; not restarting')
        now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        print('dashboard: restart requested by %s from %s at %s' % (user, self.client_address[0], now), file=sys.stderr, flush=True)
        self.reply(202, 'restarting')
        self.wfile.flush()
        try:
            run = run_script(['bash', os.path.join(HERE, 'dashboard.sh'), '--restart'], 30)
            if run.returncode != 0:
                why = (run.stderr.strip().splitlines() or ['no message'])[0]
                print('dashboard: restart FAILED (exit %d): %s' % (run.returncode, why), file=sys.stderr, flush=True)
        except subprocess.TimeoutExpired:
            print('dashboard: restart FAILED: dashboard.sh --restart did not finish in 30 s', file=sys.stderr, flush=True)
        except OSError as e:
            print('dashboard: restart FAILED: could not start dashboard.sh: %s' % e, file=sys.stderr, flush=True)

    def control(self, machine=False):
        """POST /control: one checked action, run on the Conveyor host over ssh; the reply is the host's answer.
        Same checks and order as /answer. POST /machine (machine): the pause or resume of the whole machine, the same
        way, as `conveyor.sh machine pause|resume` on the host's main; it names no project
        and changes no project's record."""
        if not self.own_page():
            return self.send_error(403)
        user = self.authed()
        if not user:
            return self.reply(401, 'log in to steer the loop')
        length = self.headers.get('Content-Length', '')
        if not length.isdigit() or int(length) > (MAX_CONTROL_BODY if machine else MAX_TEST_LIST_BODY):
            return self.send_error(413)
        try:
            body = json.loads(self.rfile.read(int(length)))
        except ValueError:
            return self.send_error(400)
        if not (machine_ok(body) if machine else control_ok(body)):
            return self.send_error(400)
        # The test map's build runs the whole suite on the build machine: an admin's to start or stop.
        if not machine and body['action'] == 'testmap' and role_of(read_store(), user) != 'admin':
            return self.reply(403, 'only an admin builds the test map')
        # Record CPU time changes the pack's test command, which every card runs: an admin's.
        if not machine and body['action'] == 'test-settings' and body['args'][0] == 'cpu-time' and role_of(read_store(), user) != 'admin':
            return self.reply(403, 'only an admin changes the test command')
        # A benchmark's run, preflight or Compare starts model sessions on the build machine: an admin's.
        if not machine and body['action'] == 'bench' and role_of(read_store(), user) != 'admin':
            return self.reply(403, 'only an admin runs benchmarks')
        # A Tests page action on a list of files is answered one result a file; only it may be over MAX_CONTROL_BODY.
        files = None if machine else test_files(body['action'], body['args'])
        if int(length) > MAX_CONTROL_BODY and not files:
            return self.send_error(413)
        if self.authed() != user:  # a logout, revoke or removal while the body was on its way
            return self.reply(401, 'log in to steer the loop')
        try:
            host, target, main, records = conveyor_host()
        except ValueError as e:
            return self.reply(503, str(e))
        if machine:
            action, args = 'machine', [body['action']]
            # On one machine main is the Board's own copy of Conveyor: the machine is steered as this checkout's.
            try:
                at = main if target else board_main()
            except ValueError as e:
                return self.reply(503, str(e))
            script = 'CONVEYOR_MAIN=%s bash %s machine %s' % (shlex.quote(at), shlex.quote(main + '/conveyor/conveyor.sh'), ' '.join(shlex.quote(a) for a in args))
        else:
            action, args = body['action'], body['args']
            record = records.get(body['repo'])  # every action names its record, never main's by default
            if record is None:
                return self.reply(409, 'conveyor/host.json has no record %s; nothing changed' % body['repo'])
            today = datetime.datetime.now(ET).strftime('%Y-%m-%d')
            script = None if files else control_script(action, args, main, today, record, user)
        print('dashboard: control %s by %s from %s' % (' '.join([action] + args), user, self.client_address[0]), file=sys.stderr, flush=True)

        def on_host(script):
            """The host's run of one script, over ssh, or here on one machine (no target): (None, its run), or (the
            HTTP code and text of the answer, None)."""
            argv = ['bash', '-c', script] if target is None else ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', target, 'bash -c ' + shlex.quote(script)]
            try:
                run = run_script(argv, CONTROL_TIMEOUT.get(action, 30))
            except subprocess.TimeoutExpired:
                return (504, '%s did not finish in time; the change may or may not have been made' % host), None
            except OSError as e:
                return (500, 'could not start %s: %s' % (argv[0], e)), None
            if run.returncode == 255 and target is not None:
                return (502, '%s did not answer' % host), None
            if run.returncode != 0:
                return (409, (run.stderr.strip().splitlines() or ['%s refused it (exit %d)' % (host, run.returncode)])[-1]), None
            return None, run
        results = None
        if files:
            # Each file on its own, as the action on that file alone (one ssh call each: a list of issue bodies in one
            # command line could pass the length the host takes for one argument). One result a file, in the list's
            # order: its id (an action's, or an issue's address), or why it was refused.
            results = []
            for f, a in files:
                err, run = on_host(control_script(action, a, main, today, record, user))
                results.append({'file': f, 'refused': err[1]} if err else {'file': f, 'id': (run.stdout.strip().splitlines() or ['done'])[-1]})
            said = '%d of %d taken: %s' % (sum('id' in r for r in results), len(results), ', '.join(r.get('id', 'refused') for r in results))
        else:
            err, run = on_host(script)
            if err:
                return self.reply(*err)
            said = (run.stdout.strip().splitlines() or ['done'])[-1]
        # Compare's answer is the whole comparison (totals, the tasks, each flipped task's facts); the ruling row keeps its last line.
        answer = run.stdout.strip() if results is None and action == 'bench' and args[:1] == ['diff'] and run.stdout.strip() else said
        try:  # the ruling row names the Board user who did it, as /answer's does
            log_ruling('Board control: %s' % ' '.join([action] + args), said, user)
        except OSError:
            return self.reply(500, '%s; ruling NOT logged' % said)
        # When the host's answer was in, by this machine's clock in whole seconds rounded up. The collector on
        # this machine stamps a snapshot (updatedAt) before it reads the host, and each record the live feed's
        # snapshot of it (readAt) when that snapshot began, so one stamped at or after this time read the record after
        # the change; the Board keeps the answer until such a snapshot comes.
        if results is not None:
            return self.json_reply(200, {'results': results}, {'X-Answered-At': str(math.ceil(time.time()))})
        self.reply(200, answer, {'X-Answered-At': str(math.ceil(time.time()))})

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == '/events':
            return self.events()
        if path == '/history':
            return self.history()
        if path == '/work':
            return self.work()
        if path == '/older':
            return self.older()
        if path == '/donewhen':
            return self.donewhen()
        if path == '/shot':
            return self.shot()
        if path == '/excerpts':
            return self.excerpts()
        if path == '/bench':
            return self.bench()
        if path in ('/me', '/users'):
            return self.users_get(path)
        if path == '/me/qr':
            return self.mfa_qr()
        return super().do_GET()

    def json_reply(self, code, data, headers=None):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def json_body(self, limit):
        """The page's JSON body, or None when the reply (413, 400) has been sent."""
        length = self.headers.get('Content-Length', '')
        if not length.isdigit() or int(length) > limit:
            self.send_error(413)
            return None
        try:
            body = json.loads(self.rfile.read(int(length)))
        except ValueError:
            body = None
        if not isinstance(body, dict):
            self.send_error(400)
            return None
        return body

    def users_get(self, path):
        """GET /me: the logged-in user's own record. GET /users: every user's (admin only, 403 for a member). Never a
        hash, a salt, a device's token hash or a setup token. LOCAL's own record is its name and role alone, with
        local: true (it has no password, MFA or devices); /users carries the "No login on this device" setting."""
        store = read_store()
        user = self.authed(store)
        if not user:
            return self.reply(401, 'log in to see users')
        users = users_of(store)
        if path == '/users' and role_of(store, user) != 'admin':
            return self.reply(403, 'only an admin manages users')

        def shown(name, u):
            return {'user': name, 'role': u.get('role'), 'created': u.get('created'), 'lastLogin': u.get('lastLogin'),
                    'mfa': bool(u.get('mfa')), 'password': bool(u.get('hash')),
                    'devices': sorted(({'id': i, 'label': d.get('label'), 'created': d.get('created'), 'used': d.get('used')}
                                       for i, d in devices_of(u).items() if isinstance(d, dict)), key=lambda d: str(d['created']))}
        if path == '/me':
            try:  # the host main /control steers, so a test can see the running server's is its own before a POST
                headers = {'X-Conveyor-Main': conveyor_host()[2]}
            except ValueError:
                headers = {}
            me = {'user': LOCAL, 'role': 'admin', 'local': True} if user == LOCAL else shown(user, users[user])
            return self.json_reply(200, me, headers)
        self.json_reply(200, {'me': user, 'users': [shown(n, users[n]) for n in sorted(users)], NO_LOGIN_HERE: no_login_here(store)})

    def users_post(self, path):
        """POST /me {action: password, old, new | mfa-setup | mfa-on, code | mfa-off | revoke, device}: a user's own
        password, MFA (mfa-setup replies {secret, uri}; mfa-on, {recovery}: each shown this once) and devices.
        POST /users {action, user, role?, device?}: add (a setup link), role, reset (a setup link; ends their sessions),
        mfa-off, revoke, remove; POST /users {action: no-login-here, on}: the "No login on this device" setting; admin
        only, 403 for a member. LOCAL has no account to change at /me (409). Each is audited."""
        if not self.own_page():
            return self.send_error(403)
        store = read_store()
        user = self.authed(store)
        if not user:
            return self.reply(401, 'log in to manage users')
        if path == '/users' and role_of(store, user) != 'admin':
            return self.reply(403, 'only an admin manages users')
        if path == '/me' and user == LOCAL:
            return self.reply(409, 'this device has no password, authenticator or devices: it needs no login')
        # /me's password change carries the old and the new password, each as long as /setup and /login take one.
        body = self.json_body(2 * MAX_LOGIN_BODY if path == '/me' else MAX_USERS_BODY)
        if body is None:
            return None
        action = body.get('action')
        if not isinstance(action, str):
            return self.send_error(400)
        if path == '/me':
            keys = {'password': {'action', 'old', 'new'}, 'mfa-off': {'action'}, 'revoke': {'action', 'device'},
                    'mfa-setup': {'action'}, 'mfa-on': {'action', 'code'}}.get(action)
            if keys is None or set(body) != keys or not all(isinstance(body[k], str) for k in keys):
                return self.send_error(400)
            name, role, device = user, None, body.get('device')
            if action == 'password' and password_problem(body['new'], user):
                return self.reply(400, password_problem(body['new'], user))
        elif action == 'no-login-here':
            if set(body) != {'action', 'on'} or not isinstance(body['on'], bool):
                return self.send_error(400)
            name, role, device = LOCAL, None, None
        else:
            keys = {'add': {'role'}, 'role': {'role'}, 'revoke': {'device'}}.get(action, set()) | {'action', 'user'}
            if action not in ('add', 'role', 'reset', 'mfa-off', 'revoke', 'remove') or set(body) != keys \
                    or not all(isinstance(body[k], str) for k in keys):
                return self.send_error(400)
            name, role, device = body['user'], body.get('role'), body.get('device')

        def act(store):
            # Checked again under the store's lock, against the store the change is made to: a login ended, a role
            # taken away or a password reset while this request's body was on its way refuses it.
            users = users_of(store)
            if self.authed(store) != user:
                raise Refused('log in to manage users', 401)
            if path == '/users' and role_of(store, user) != 'admin':
                raise Refused('only an admin manages users', 403)
            if action == 'no-login-here':
                store[NO_LOGIN_HERE] = body['on']
                return {'done': action, NO_LOGIN_HERE: body['on']}
            if action == 'password':
                if not password_ok(store, user, body['old']):
                    # 403, not 401: the user is logged in, and the page sends a 401 to /login.
                    raise Refused('the current password is wrong', 403)
                return set_hash(store, need(store, name), body['new'])
            if action == 'mfa-setup':
                return mfa_setup(users[user], user)
            if action == 'mfa-on':
                return {'recovery': mfa_on(users[user], body['code'], time.time())}
            token = user_action(store, action, name, role, device)
            return {'link': '/setup#' + token} if token else {'done': action}
        try:
            shown = change_store(act)
        except Refused as e:
            return self.reply(e.code, str(e))
        audit(user, 'set-password' if action == 'password' else action, name, **({'role': role} if role else {}),
              **({'device': device} if device else {}), **({'on': body['on']} if action == 'no-login-here' else {}))
        print('dashboard: user %s %s by %s from %s' % (action, name, user, self.client_address[0]), file=sys.stderr, flush=True)
        self.json_reply(200, shown or {'done': action})

    def mfa_qr(self):
        """GET /me/qr: the QR code (SVG) of the logged-in user's MFA setup under way, for their authenticator app."""
        user = self.authed()
        if not user:
            return self.reply(401, 'log in to set up MFA')
        pending = users_of(read_store()).get(user, {}).get('totpPending')
        if not pending:
            return self.reply(404, 'no MFA setup is under way')
        uri = totp(mfa_key().decrypt(pending.encode()).decode()).provisioning_uri(name=user, issuer_name=MFA_ISSUER)
        out = io.BytesIO()
        segno.make(uri, error='m').save(out, kind='svg', scale=6, border=4, dark='#000', light='#fff')
        body = out.getvalue()
        self.send_response(200)
        self.send_header('Content-Type', 'image/svg+xml')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def setup_password(self):
        """POST /setup {token, password}: a setup link sets its user's password, once, within SETUP_TTL."""
        if not self.own_page():
            return self.send_error(403)
        body = self.json_body(MAX_LOGIN_BODY)
        if body is None:
            return None
        if set(body) != {'token', 'password'} or not all(isinstance(body[k], str) for k in body):
            return self.send_error(400)
        rec = read_store().get('setups', {}).get(sha(body['token'])) or {}  # its user's name is in the login body
        if password_problem(body['password'], rec.get('user', '')):
            return self.reply(400, password_problem(body['password'], rec.get('user', '')))

        def use(store):
            drop_setups(store)  # the expired ones
            rec = store['setups'].pop(sha(body['token']), None)
            if rec is None or rec.get('user') not in users_of(store):
                return None
            set_hash(store, store['users'][rec['user']], body['password'])
            return rec['user']
        name = change_store(use)
        if name is None:
            return self.reply(410, 'this setup link has been used or has expired: ask an admin for a new one')
        audit(name, 'setup', name)
        self.reply(200, 'password set: log in')

    def history(self):
        """GET /history: the Landed, Metrics, Cost and Declined parts built from every entry, where data.js holds the
        newest the snapshot keeps: dashboard.sh --history's JSON, which it reads from the host at most once a minute.
        Its copy of the last minute is served from the file, with no process (fresh_history). The page asks for it
        when one of those panels is drawn. 502 with the reason when it gives none."""
        if not self.authed():
            return self.reply(401, 'log in to see the history')
        body = fresh_history(self.directory)
        if body is None:
            try:
                run = run_script(['bash', os.path.join(HERE, 'dashboard.sh'), '--history'], HISTORY_LIMIT)
            except subprocess.TimeoutExpired:
                return self.reply(502, 'the history did not come in %d s' % HISTORY_LIMIT)
            except OSError as e:
                return self.reply(502, 'could not start dashboard.sh: %s' % e)
            if run.returncode != 0:
                return self.reply(502, (run.stderr.strip().splitlines() or ['no message'])[-1])
            body = run.stdout.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def work(self):
        """GET /work: the Health panel's Work now, what keeps the Conveyor host busy now: dashboard.sh --work's JSON,
        read afresh on each ask (the page asks when the owner opens Work now or reads it again). 502 with the reason
        when it gives none."""
        if not self.authed():
            return self.reply(401, 'log in to see what keeps the machine busy')
        try:
            run = run_script(['bash', os.path.join(HERE, 'dashboard.sh'), '--work'], WORK_LIMIT)
        except subprocess.TimeoutExpired:
            return self.reply(502, 'the work reading did not come in %d s' % WORK_LIMIT)
        except OSError as e:
            return self.reply(502, 'could not start dashboard.sh: %s' % e)
        if run.returncode != 0:
            return self.reply(502, (run.stderr.strip().splitlines() or ['no message'])[-1])
        body = run.stdout.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def older(self):
        """GET /older?repo=<repo>&file=<test file>: the older runs and test edits of one test file, which data.js does
        not carry: dashboard.sh --older's JSON, read afresh on each ask (the Tests page asks when a file's Timeline is
        opened). 400 for a repo or file of another shape, 502 with the reason when it gives none."""
        if not self.authed():
            return self.reply(401, 'log in to see the older runs')
        q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        repo, file = (q.get('repo') or [''])[0], (q.get('file') or [''])[0]
        if not REPO.fullmatch(repo) or not TEST_FILE.fullmatch(file):
            return self.reply(400, 'no repo or test file of the shape the Board names')
        try:
            run = run_script(['bash', os.path.join(HERE, 'dashboard.sh'), '--older', repo, file], OLDER_LIMIT)
        except subprocess.TimeoutExpired:
            return self.reply(502, 'the older runs did not come in %d s' % OLDER_LIMIT)
        except OSError as e:
            return self.reply(502, 'could not start dashboard.sh: %s' % e)
        if run.returncode != 0:
            return self.reply(502, (run.stderr.strip().splitlines() or ['no message'])[-1])
        body = run.stdout.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def donewhen(self):
        """GET /donewhen?repo=<repo>&card=<card id>: a card's last Done-when check item by item, which data.js does not
        carry: dashboard.sh --donewhen's JSON, read afresh on each ask (the Board asks when a card's Done-when line is
        opened)."""
        return Handler.card_read(self, '--donewhen', 'the Done-when check')

    def excerpts(self):
        """GET /excerpts?repo=<repo>&card=<card id>: the lines a card's review findings cite, as each review kept them
        from the tree it read, which data.js does not carry: dashboard.sh --excerpts's JSON, read afresh on each ask (the
        Board asks when a finding's place is opened)."""
        return Handler.card_read(self, '--excerpts', 'the reviewed lines')

    def card_read(self, flag, what):
        """One card's detail from dashboard.sh <flag> <repo> <card>, for GET /donewhen and GET /excerpts. 400 for a repo
        or card of another shape, 502 with the reason when it gives none."""
        if not self.authed():
            return self.reply(401, 'log in to see %s' % what)
        q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        repo, card = (q.get('repo') or [''])[0], (q.get('card') or [''])[0]
        if not REPO.fullmatch(repo) or not CARD.fullmatch(card):
            return self.reply(400, 'no repo or card of the shape the Board names')
        try:
            run = run_script(['bash', os.path.join(HERE, 'dashboard.sh'), flag, repo, card], DONEWHEN_LIMIT)
        except subprocess.TimeoutExpired:
            return self.reply(502, '%s did not come in %d s' % (what, DONEWHEN_LIMIT))
        except OSError as e:
            return self.reply(502, 'could not start dashboard.sh: %s' % e)
        if run.returncode != 0:
            return self.reply(502, (run.stderr.strip().splitlines() or ['no message'])[-1])
        body = run.stdout.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def shot(self):
        """GET /shot?repo=<repo>&card=<card>&file=<file>: one screenshot a card waiting for the owner's yes kept (the
        snapshot's needsYou.waiting[].shots), read from the host by dashboard.sh --shot, which gives it as base64: the
        image goes only from Conveyor's host to this page. 400 for a repo, card or file of another shape, 502 with
        the reason when the host gives none."""
        if not self.authed():
            return self.reply(401, 'log in to see the screenshots')
        q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        repo, card, file = ((q.get(k) or [''])[0] for k in ('repo', 'card', 'file'))
        m = SHOT.fullmatch(file)
        if not REPO.fullmatch(repo) or not CARD.fullmatch(card) or not m:
            return self.reply(400, 'no repo, card or screenshot of the shape the Board names')
        try:
            run = run_script(['bash', os.path.join(HERE, 'dashboard.sh'), '--shot', repo, card, file], SHOT_LIMIT)
        except subprocess.TimeoutExpired:
            return self.reply(502, 'the screenshot did not come in %d s' % SHOT_LIMIT)
        except OSError as e:
            return self.reply(502, 'could not start dashboard.sh: %s' % e)
        try:
            body = base64.b64decode(run.stdout) if run.returncode == 0 else b''
        except (binascii.Error, ValueError):
            body = b''
        if not body:
            return self.reply(502, (run.stderr.strip().splitlines() or ['the host gave no screenshot'])[-1])
        self.send_response(200)
        self.send_header('Content-Type', SHOT_TYPES[m.group(2)])
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Cache-Control', 'private, max-age=3600')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def bench(self):
        """GET /bench?repo=<repo>[&run=<run id>]: the Benchmarks tab's history (every run with each arm's figures, and
        the arms) or one run's tasks by arm, which data.js does not carry: dashboard.sh --bench's JSON, read afresh on
        each ask (the tab asks when it is shown, and when a run is opened). 400 for a repo or run of another shape, 502
        with the reason when it gives none."""
        if not self.authed():
            return self.reply(401, 'log in to see the benchmarks')
        q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        repo, run_id = (q.get('repo') or [''])[0], (q.get('run') or [''])[0]
        if not REPO.fullmatch(repo) or not (run_id == '' or BENCH_RUN.fullmatch(run_id)):
            return self.reply(400, 'no repo or run of the shape the Board names')
        try:
            run = run_script(['bash', os.path.join(HERE, 'dashboard.sh'), '--bench', repo] + ([run_id] if run_id else []), BENCH_LIMIT)
        except subprocess.TimeoutExpired:
            return self.reply(502, 'the benchmarks did not come in %d s' % BENCH_LIMIT)
        except OSError as e:
            return self.reply(502, 'could not start dashboard.sh: %s' % e)
        if run.returncode != 0:
            return self.reply(502, (run.stderr.strip().splitlines() or ['no message'])[-1])
        body = run.stdout.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def events(self):
        """GET /events: data.js's changes as server-sent events, one panel each."""
        feed = FEED[0]
        if not self.authed():
            return self.reply(401, 'log in to follow the dashboard')
        if feed is None:
            return self.reply(503, 'the live feed is not running')
        with feed.cond:
            if feed.followers >= MAX_FOLLOWERS:
                return self.reply(503, 'too many pages are following the dashboard')
            feed.followers += 1
        try:
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
            self.send_header('X-Accel-Buffering', 'no')
            self.send_header('Connection', 'close')  # a stream with no Content-Length ends with its connection
            self.end_headers()

            def send(kind, key=None):
                self.wfile.write(events.event(kind, key))  # encoded once a version for every follower
                self.wfile.flush()

            feed.look()  # data.js as it is now, not as it was at the last look
            version, data, texts, events = feed.wait(None, 0)
            parts = None  # what this page has (each panel's text, the feed's): nothing until its snapshot
            checked = time.monotonic()
            while True:
                if data is not None and parts is None:
                    send('snapshot')
                    parts = texts
                v, data, texts, events = feed.wait(version, PING)
                # The login is checked each PING whether or not data flows: changes coming faster than PING must not
                # keep a logged-out or revoked page following.
                if v == version or data is None or time.monotonic() - checked >= PING:
                    if not self.authed():
                        return  # logged out, or the device revoked: the stream ends with the login
                    checked = time.monotonic()
                if v == version or data is None:
                    self.wfile.write(b': ping\n\n')
                    self.wfile.flush()
                    continue
                version = v
                if parts is None:
                    continue  # its first data: the snapshot, above
                changed = [k for k in texts if parts.get(k) != texts[k]]
                for k in changed:
                    send('panel', k)
                if not changed:
                    send('updated')
                parts = texts
        except (OSError, ssl.SSLError, ValueError):
            return  # the page went away
        finally:
            with feed.cond:
                feed.followers -= 1
            self.close_connection = True

    def do_POST(self):
        if self.path == '/login':
            return self.login()
        if self.path == '/setup':
            return self.setup_password()
        if self.path == '/restart':
            return self.restart_collector()
        if self.path == '/control':
            return self.control()
        if self.path == '/machine':
            return self.control(machine=True)
        if self.path in ('/me', '/users'):
            return self.users_post(self.path)
        if self.path == '/time':
            return self.set_time()
        if self.path != '/answer' or not self.own_page():
            return self.send_error(403)
        user = self.authed()
        if not user:
            return self.reply(401, 'log in to answer')
        length = self.headers.get('Content-Length', '')
        if not length.isdigit() or int(length) > MAX_ANSWER_BODY:
            return self.send_error(413)
        try:
            body = json.loads(self.rfile.read(int(length)))
        except ValueError:
            return self.send_error(400)
        if not answer_ok(body):
            return self.send_error(400)
        if self.authed() != user:  # a logout, revoke or removal while the body was on its way
            return self.reply(401, 'log in to answer')
        try:  # the ledger of the decision's record, as the Board read it, never the Board's own checkout's
            env = dict(os.environ, CONVEYOR_LEDGER=record_ledger(body['repo']))
        except ValueError as e:
            return self.reply(409, '%s; nothing recorded' % e)
        kept = read_unsent(body['id'])
        if kept and kept.get('askedAt') == body['askedAt'] and kept.get('answer') == body['answer'] and self.resend(kept, env):
            return
        # An argument list, no shell. --asked-at: decision.sh refuses a decision re-asked or reopened since the page
        # read it, and one already answered; this write can do nothing else to the ledger.
        try:
            run = run_script(['bash', os.path.join(HERE, 'decision.sh'), 'answer', body['id'], body['answer'],
                              '--asked-at', body['askedAt']], 15, env)
        except subprocess.TimeoutExpired:
            return self.reply(500, 'decision.sh did not finish in 15 s; the answer may not be recorded')
        if run.returncode != 0:
            return self.reply(409, (run.stderr.strip().splitlines() or ['decision.sh refused the answer'])[0])
        try:
            rid = log_ruling(json.loads(run.stdout.strip().splitlines()[-1])['question'], body['answer'], user)
        except (OSError, ValueError, KeyError, IndexError):
            # Loud like ruling-log.sh: the answer is in the ledger, and nothing can cite it until it is logged.
            return self.reply(500, 'answer recorded, ruling NOT logged')
        self.reply(200, 'recorded, ruling %s logged' % rid)

    def resend(self, rec, env):
        """The page sent an answer again for a record an earlier version kept when its message to main never went. The
        decision's current row decides: an answer corrected or a decision reopened since is retired; one that still
        stands is cleared. Either way no ledger row, no ruling and no message is written. False, with nothing replied,
        when this ledger's decision is still open at the same askedAt: the kept answer was never recorded here (the
        record names no project, so it may be another project's), and the answer is recorded as any other."""
        try:
            run = run_script(['bash', os.path.join(HERE, 'decision.sh'), 'list'], 15, env)
            row = next(d for d in json.loads(run.stdout) if d['id'] == rec['id'])
        except (subprocess.TimeoutExpired, ValueError, StopIteration, KeyError, TypeError):
            self.reply(500, 'could not read the decision to check the answer still stands; try again')
            return True
        if row.get('answeredAt') is None and row.get('askedAt') == rec['askedAt']:
            return False
        if row.get('answeredAt') is None or row.get('askedAt') != rec['askedAt']:
            drop_unsent(rec['id'])
            self.reply(409, 'superseded: the decision was reopened')
        elif row.get('answer') != rec['answer']:
            drop_unsent(rec['id'])
            self.reply(409, 'superseded: the decision now says %s' % row.get('answer'))
        else:
            drop_unsent(rec['id'])
            self.reply(200, 'recorded, ruling %s logged' % rec.get('ruling'))
        return True

class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 128  # the default 5 drops a burst of TLS connections (a page loads several files at once)

    def handle_error(self, request, client_address):
        # A client that cannot finish the TLS handshake (plain HTTP, a scanner) or goes quiet is noise, not a fault.
        if not isinstance(sys.exc_info()[1], (ssl.SSLError, ConnectionError, TimeoutError)):
            super().handle_error(request, client_address)


def serve(port, directory):
    if not (os.path.exists(CERT) and os.path.exists(KEY)):
        sys.exit('no certificate: run dashboard_server.py make-cert')
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(CERT, KEY)
    srv = Server(('0.0.0.0', port), functools.partial(Handler, directory=directory))
    FEED[0] = Feed(directory)
    threading.Thread(target=FEED[0].run, daemon=True).start()
    # The handshake runs in each request's own thread: done at accept(), one silent client would stop the whole server.
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True, do_handshake_on_connect=False)
    srv.serve_forever()


if __name__ == '__main__':
    cmd, args = (sys.argv[1:2] or [''])[0], sys.argv[2:]
    if cmd == 'make-cert':
        cli_make_cert('--force' in args)
    elif cmd == 'add-user' and len([a for a in args if a != '--admin']) == 1 and len(args) <= 2:
        cli_add_user(next(a for a in args if a != '--admin'), '--admin' in args)
    elif cmd == 'set-role' and len(args) == 2:
        cli_action('role', args[0], args[1])
        print('%s is now %s' % (args[0], args[1]))
    elif cmd == 'set-password' and len(args) == 1:
        cli_set_password(args[0])
    elif cmd == 'remove-user' and len(args) == 1:
        cli_action('remove', args[0])
        print('%s removed' % args[0])
    elif cmd == 'mfa-off' and len(args) == 1:
        cli_action('mfa-off', args[0])
        print('MFA off for %s' % args[0])
    elif cmd == 'can-open':
        cli_can_open()
    elif cmd == 'devices' and len(args) <= 1:
        cli_devices(*args)
    elif cmd == 'revoke' and len(args) == 1:
        cli_revoke(args[0])
    elif cmd.isdigit() and len(args) == 1:
        serve(int(cmd), args[0])
    else:
        sys.exit('usage: dashboard_server.py <port> <directory> | make-cert [--force] | add-user <user> [--admin] | set-role <user> admin|member'
                 ' | set-password <user> | remove-user <user> | mfa-off <user> | can-open | devices [<user>] | revoke <id>|all')
