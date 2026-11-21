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
and names no record); dismiss one plugin problem a Foreman noted through `POST /plugin-dismiss` (its line is
removed from that Foreman's plugin-bugs.md; nothing is filed); and manage
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
the page asks for it at most once a minute while its Landed, Metrics, Cost or Declined panel is shown and not
collapsed. It is built again only when the ledger changed (or a POST /control was taken), one build at a time, and its
ETag is that of the copy built for the ledger key: an If-None-Match that names it is a 304.
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
import platform
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


# This server is one module in six files: each part below runs in this module's namespace, in this order, as if its
# text stood here, so a name is one name wherever it is read (a name replaced on this module, as a test replaces
# run_script, role_of or SCRYPT, is replaced for every part).
def run_part(path):
    with open(path, encoding='utf-8') as f:
        exec(compile(f.read(), path, 'exec'), globals())


run_part(os.path.join(HERE, 'dashboard_server_base.py'))
run_part(os.path.join(HERE, 'dashboard_server_control.py'))
run_part(os.path.join(HERE, 'dashboard_server_auth.py'))
run_part(os.path.join(HERE, 'dashboard_server_pages.py'))
run_part(os.path.join(HERE, 'dashboard_server_handler.py'))


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
