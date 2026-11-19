#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# How the page server (dashboard_server.py) sends the Board's files: the page's first load is about 20 files and a
# 1 MB data.js, over TLS. Bug each case catches: data.js, a script or the stylesheet sent uncompressed to a browser
# that takes gzip (or compressed to one that does not, which cannot read it); a kept copy that is not made again when
# the file changes; a connection closed after each reply, so each file of a first load costs a TLS handshake; and,
# with connections kept, a reply with no end (the /events stream) or a POST body left unread on a kept connection.
# The server runs in this process, over plain HTTP: what is checked is the handler, not TLS. Its requests come from
# this device, which "No login on this device" (on with no value stored) lets in with no login.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PY=$XDG_DATA_HOME/conveyor/board-venv/bin/python3
"$PY" -c 'import pyotp, segno, cryptography' || { echo "FAIL: the Board's virtualenv $PY lacks its packages: run conveyor.sh setup" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/out" "$T/auth"
CONVEYOR_DASHBOARD_AUTH=$T/auth/dashboard-auth.json CONVEYOR_RULING_LOG=$T/rulings.jsonl XDG_CONFIG_HOME=$T/config \
  HOME=$T CONVEYOR_MAIN=$T "$PY" -I - "$HERE/.." "$T/out" <<'EOF'
import functools, gzip, http.client, os, sys, threading
sys.path.insert(0, sys.argv[1])
import dashboard_server as ds

OUT = sys.argv[2]
FILES = {'data.js': b'window.DASH = {"panels": {}, "pad": "%s"};\n' % (b'x' * 4000), 'app.js': b'(function () { "use strict"; }());\n' * 200}
for name, body in FILES.items():
    with open(os.path.join(OUT, name), 'wb') as f:
        f.write(body)
srv = ds.Server(('127.0.0.1', 0), functools.partial(ds.Handler, directory=OUT))
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, kwargs={'poll_interval': 0.02}, daemon=True).start()
HOST = 'localhost:%d' % PORT
passed = [0]


def check(case, ok, why=''):
    if not ok:
        sys.exit('FAIL: %s: %s' % (case, why))
    passed[0] += 1


def get(c, path, headers=None):
    """(status, lower-cased headers, body) of GET path on the connection c."""
    c.request('GET', path, headers={'Host': HOST, **(headers or {})})
    r = c.getresponse()
    return r.status, {k.lower(): v for k, v in r.getheaders()}, r.read()


c = http.client.HTTPConnection('127.0.0.1', PORT, timeout=10)
# D2: data.js and app.js come gzip-compressed to a browser that takes gzip, and plain to one that does not.
for name, body in FILES.items():
    s, h, got = get(c, '/%s?1' % name, {'Accept-Encoding': 'gzip, deflate, br'})
    check('%s_gzip' % name, s == 200 and h.get('content-encoding') == 'gzip' and gzip.decompress(got) == body
          and len(got) < len(body) and h.get('content-length') == str(len(got)), (s, h))
    check('%s_varies' % name, h.get('vary') == 'Accept-Encoding', h)
    # The page's code is revalidated on each load (no-cache): an unchanged file is a 304, not its bytes again.
    s, _, got = get(c, '/%s' % name, {'Accept-Encoding': 'gzip', 'If-Modified-Since': h.get('last-modified', '')})
    check('%s_gzip_not_modified' % name, s == 304 and got == b'', s)
    s, h, got = get(c, '/%s?1' % name)
    check('%s_plain' % name, s == 200 and 'content-encoding' not in h and got == body, (s, h, got[:40]))
    s, h, got = get(c, '/%s?1' % name, {'Accept-Encoding': 'gzip;q=0, identity'})
    check('%s_gzip_refused' % name, s == 200 and 'content-encoding' not in h and got == body, (s, h))
# The kept copy is made again when the file changes: never the old file's compressed bytes.
new = b'window.DASH = {"panels": {"belt": {}}, "pad": "%s"};\n' % (b'y' * 6000)
with open(os.path.join(OUT, 'data.js'), 'wb') as f:
    f.write(new)
s, h, got = get(c, '/data.js?2', {'Accept-Encoding': 'gzip'})
check('changed_file_compressed_again', gzip.decompress(got) == new, got[:40])
# Issue 550: the page polls data.js at one address and revalidates it by ETag. data.js rewritten twice within one
# second has one Last-Modified for both texts: a 304 by date (or by a tag made from it) keeps the first text in the
# page. The tag is made from the file's stat, so the second text is a 200; the unchanged file is a 304.
first, second = {}, int(os.stat(os.path.join(OUT, 'data.js')).st_mtime) * 10**9
for n, text in enumerate((b'window.DASH = {"panels": {"a": {}}};\n', b'window.DASH = {"panels": {"bb": {}}};\n')):
    with open(os.path.join(OUT, 'data.js'), 'wb') as f:
        f.write(text)
    os.utime(os.path.join(OUT, 'data.js'), ns=(second + n + 1, second + n + 1))
    for enc in ('gzip', 'identity'):
        if n == 0:
            s, h, _ = get(c, '/data.js', {'Accept-Encoding': enc})
            check('etag_sent_%s' % enc, s == 200 and h.get('etag'), h)
            first[enc] = h
            continue
        s, h, got = get(c, '/data.js', {'Accept-Encoding': enc, 'If-None-Match': first[enc]['etag'],
                                        'If-Modified-Since': first[enc]['last-modified']})
        check('same_second_rewrite_%s' % enc, s == 200 and (gzip.decompress(got) if enc == 'gzip' else got) == text
              and h.get('last-modified') == first[enc]['last-modified'] and h.get('etag') != first[enc]['etag'], (s, h, got[:40]))
        s, h2, got = get(c, '/data.js', {'Accept-Encoding': enc, 'If-None-Match': h['etag']})
        check('unchanged_etag_304_%s' % enc, s == 304 and got == b'' and h2.get('etag') == h['etag'], (s, h2))
# The Board at / (its index.html) and the sign-in page at /login (login.html) are served by other routes than the
# file path: without a tag there, a browser revalidates them by date only and a same-second rewrite stays unseen.
for route, name in (('/', 'index.html'), ('/login', 'login.html')):
    body = b'<!doctype html><title>%s</title>\n' % name.encode()
    with open(os.path.join(OUT, name), 'wb') as f:
        f.write(body)
    s, h, got = get(c, route)
    check('etag_%s' % name, s == 200 and got == body and h.get('etag'), (s, h, got[:40]))
    for match in (h.get('etag'), '*'):
        s, h2, got = get(c, route, {'If-None-Match': match})
        check('etag_304_%s_%s' % (name, match), s == 304 and got == b'' and h2.get('etag') == h['etag'], (s, h2))
# D3: two requests on one connection are both answered: the server speaks HTTP/1.1 and keeps it open.
sock = c.sock
s1 = get(c, '/app.js')[0]
s2 = get(c, '/data.js?3')[0]
check('one_connection_two_requests', s1 == 200 and s2 == 200 and c.sock is sock and sock is not None, (s1, s2, c.sock, sock))
# The /events stream has no Content-Length: it says Connection: close, so the browser does not wait on it for a reply.
ds.FEED[0] = ds.Feed(OUT)
c.request('GET', '/events', headers={'Host': HOST})
r = c.getresponse()
check('events_stream_closes', r.status == 200 and r.getheader('Connection') == 'close' and r.fp.readline() == b'event: snapshot\n',
      (r.status, r.getheaders()))
c.close()
# A POST refused before its body is read (here: not logged in, from another device) ends its connection, so the
# body left unread is never read as the next request on it.
other = '192.0.2.1:%d' % PORT
c.request('POST', '/control', body=b'{"action": "pause", "args": [], "repo": "sample"}',
          headers={'Host': other, 'Origin': 'https://' + other, 'Content-Type': 'application/json'})
r = c.getresponse()
r.read()
check('refused_post_closes', r.status == 401 and r.getheader('Connection') == 'close', (r.status, r.getheaders()))
check('next_request_after_post', get(c, '/app.js', {'Host': other})[0] == 302, 'the unread body was read as a request')
c.close()
srv.shutdown()
print('PASS: dashboard-server-http (%d checks)' % passed[0])
EOF
