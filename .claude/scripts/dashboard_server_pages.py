# SPDX-License-Identifier: Apache-2.0
# A part of dashboard_server.py, run in its namespace (run_part()), not a module of its own: the first half of the
# page server's request handler, which Handler (dashboard_server_handler.py) takes from Pages.


def notes_lock(path):
    """The lock file serve appends its price notes to the plugin-bugs.md path under (noprice.lock beside it, noprice(),
    lib/control.sh), opened: the caller takes the lock on it, and closing it frees the lock."""
    # os is the base part's, run in this namespace: globals() names it where a linter reads this file alone.
    return open(globals()['os'].path.join(globals()['os'].path.dirname(path), 'noprice.lock'), 'a')


NOTE_HOLDS = {}  # a plugin-bugs.md path and note line, and the lock of the File and Dismiss requests on it (note_hold())


def note_hold(path, line):
    """The lock a File or Dismiss of the note line in path holds from its check that the note is there, through gh's
    filing, to the note's removal: the server answers each request on a thread of its own, so a second tab's File of
    the same note would find it still there and file it again. It is one note's, so a slow filing holds up no request
    on another note, and a Preview, which changes nothing, takes none. It is this process's own (serve takes no part
    in it): a gh call can take GH_LIMIT, and noprice.lock, which serve's appends wait on, is held only for the removal.
    dict.setdefault is one step under the interpreter's lock, so two threads get the same lock."""
    # threading is the base part's, run in this namespace: globals() names it where a linter reads this file alone.
    return NOTE_HOLDS.setdefault((path, line), globals()['threading'].Lock())


class Pages:
    """Handler's methods that serve the page's files and the login, and take POST /time, the plugin notes and POST
    /restart; Handler holds the rest and its class settings. Handler puts Pages before SimpleHTTPRequestHandler, so
    super() here is SimpleHTTPRequestHandler's, as it was in Handler."""

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
        """POST /time {time}: the Board's Time setting (12-hour or 24-hour), as a browser last sent it: on each change, and
        on opening the Board only once per browser (app.js TIME_SENT_KEY), and only when its Time is not the default.
        The send on opening is {time, first: true}: it is kept only when no time.json is here yet, else refused with
        409, so a Time set since, maybe in another browser, stands. The file is linked into place, which fails when
        one is there, so no Time sent between the check and the write is overwritten.
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
        if set(body) - {'first'} != {'time'} or body['time'] not in ('12-hour', '24-hour') or body.get('first', True) is not True:
            return self.send_error(400)
        first = 'first' in body
        tmp = os.path.join(self.directory, '.time.json.%d' % threading.get_ident())
        try:
            with open(tmp, 'w') as f:
                json.dump({'time': body['time']}, f)
            os.chmod(tmp, 0o644)
            # os is the base part's, run in this namespace: globals() names it where a linter reads this file alone.
            fs = globals()['os']
            kept = fs.path.join(self.directory, 'time.json')
            if first:
                try:
                    fs.link(tmp, kept)
                except FileExistsError:
                    fs.remove(tmp)
                    return self.reply(409, 'a Time is kept already')
                fs.remove(tmp)
            else:
                fs.replace(tmp, kept)
        except OSError as e:
            try:
                os.remove(tmp)  # each thread names its own: one left behind would never be replaced
            except OSError:
                pass
            return self.reply(500, 'the Time could not be kept: %s' % e.strerror)
        print('dashboard: Time set to %s by %s from %s' % (body['time'], user, self.client_address[0]), file=sys.stderr, flush=True)
        self.reply(200, 'kept')

    def plugin_note(self, act):
        """POST /plugin-dismiss, /plugin-preview or /plugin-file, each {file, line}, /plugin-file with {title, body} too:
        one note of the Plugin problems pane. file must be a plugin-bugs.md the Board read (the Health part of data.js
        names it), so no other file can be read or written; line is the note, whole. Same checks and order as /answer.
        dismiss removes the first line of file that is line; every other line stays; nothing is filed and gh is not
        run. preview answers the issue the note proposes as JSON {title, body, repo} (note_issue(), plugin_repo()) and writes nothing. file
        files the issue the owner confirmed, with its edited title and body: conveyor/privacy/check.sh first, where a
        hit files nothing and the reply names each hit (422); then the issue is created on the repository
        .claude-plugin/plugin.json names, through conveyor.sh gh-write (the engine's privacy gate, gh_write(),
        lib/issues.sh) run on this machine's checkout (board_main()); only once gh answers the new issue's link is the note removed, as dismiss
        removes it, and the reply is that link. A failed gh call leaves the note and the reply is gh's error (502). A note
        that names the issue it was filed as (NOTE_FILED) is neither previewed nor filed (409); it can be dismissed."""
        if not self.own_page():
            return self.send_error(403)
        user = self.authed()
        if not user:
            return self.reply(401, 'log in to %s a note' % act)
        body = self.json_body(MAX_FILE_BODY if act == 'file' else MAX_DISMISS_BODY)
        if body is None:
            return None
        if set(body) != ({'file', 'line', 'title', 'body'} if act == 'file' else {'file', 'line'}) \
                or not all(isinstance(body[k], str) for k in body) \
                or not body['line'].startswith('- ') or '\n' in body['line'] or '\r' in body['line']:
            return self.send_error(400)
        if act == 'file' and (not body['title'].strip() or '\n' in body['title'] or '\r' in body['title']):
            return self.send_error(400)
        try:
            with open(os.path.join(self.directory, 'data.js'), encoding='utf-8') as f:
                text = f.read()
            bugs = json.loads(text[text.index('{'):text.rindex('}') + 1])['panels']['health']['data']['pluginBugs']
            files = {b['file'] for b in bugs if isinstance(b, dict) and isinstance(b.get('file'), str)}
        except (OSError, ValueError, KeyError, TypeError):
            files = set()
        path = body['file']
        if path not in files:
            return self.reply(409, 'the Board did not read plugin problems from that file; nothing was changed')
        if act == 'preview':
            return self.note_act(act, body, path, user)
        # One File or Dismiss of the note at a time, from the check that it is there to its removal (note_hold()): a
        # second File of the note waits, then finds it gone (409), so it is filed once.
        with note_hold(path, body['line']):
            return self.note_act(act, body, path, user)

    def note_act(self, act, body, path, user):
        """plugin_note()'s work on the note line body['line'] of path, checked already; a File or Dismiss runs it
        under note_hold()."""
        try:
            with open(path, encoding='utf-8') as f:
                held = any(x.rstrip('\n') == body['line'] for x in f)
        except (OSError, ValueError) as e:  # ValueError: a file that is not UTF-8
            return self.reply(500, 'the note could not be read: %s' % (getattr(e, 'strerror', None) or e))
        if not held:
            return self.reply(409, 'that note is no longer in the file; nothing was changed')
        if act != 'dismiss' and NOTE_FILED.search(body['line']):
            return self.reply(409, 'that note names the issue it was filed as; nothing was filed')
        if act == 'preview':
            try:
                repo = plugin_repo()
            except ValueError as e:
                return self.reply(500, 'the note cannot be filed: %s' % e)
            title, text = note_issue(body['line'])
            return self.reply(200, json.dumps({'title': title, 'body': text, 'repo': repo}))
        url = None
        if act == 'file':
            url = self.note_file(body, user)
            if not url:
                return None  # note_file() replied why nothing was filed
        return self.note_remove(body, path, url, user)

    def note_file(self, body, user):
        """note_act()'s filing of the issue body names: the new issue's link, or None once it has replied why nothing
        was filed."""
        # The base and control parts' names, run in this namespace: globals() names them where a linter reads this file alone.
        os, re, subprocess, sys, plugin_repo, privacy_hits, board_main, PLUGIN_ROOT, GH_LIMIT = (globals()[n] for n in (
            'os', 're', 'subprocess', 'sys', 'plugin_repo', 'privacy_hits', 'board_main', 'PLUGIN_ROOT', 'GH_LIMIT'))
        try:
            repo, hits = plugin_repo(), privacy_hits(body['title'], body['body'])
        except ValueError as e:
            return self.reply(500, f'nothing was filed: {e}')
        if hits:
            return self.reply(422, 'nothing was filed: the privacy check found ' + '; '.join(hits))
        try:
            main = board_main()
        except ValueError as e:
            return self.reply(500, f'nothing was filed: {e}')
        try:
            r = subprocess.run(['bash', os.path.join(PLUGIN_ROOT, 'conveyor', 'conveyor.sh'), 'gh-write', 'issue', 'create',
                                '--repo', repo, '--title', body['title'], '--body-file', '-'],
                               cwd=main, env=dict(os.environ, CONVEYOR_MAIN=main), input=body['body'],
                               capture_output=True, text=True, timeout=GH_LIMIT)
        except (OSError, subprocess.SubprocessError) as e:
            return self.reply(502, f"nothing was filed: the issue could not be created: {getattr(e, 'strerror', None) or e}")
        url = next((x for x in reversed(r.stdout.split())
                    if re.fullmatch(rf'https://github\.com/{re.escape(repo)}/issues/[0-9]+', x, re.I)), None)
        if r.returncode or not url:
            said = (r.stderr.strip() or r.stdout.strip() or f'exit {r.returncode}').splitlines()[-1]
            return self.reply(502, f'nothing was filed: the issue could not be created: {said}')
        print(f'dashboard: plugin problem filed as {url} by {user} from {self.client_address[0]}', file=sys.stderr, flush=True)
        return url

    def note_remove(self, body, path, url, user):
        """note_act()'s removal of the note line body['line'] from path, once dismissed or filed as url."""
        # Read again: gh may have taken a while, and the Foreman may have noted another problem since. The read, the
        # edit and the replace hold the lock serve's price notes are appended under (noprice(), lib/control.sh:
        # noprice.lock beside the file), so a note appended meanwhile is not lost under the Board's older copy.
        tmp = '%s.dismiss.%d' % (path, threading.get_ident())
        lock = None
        try:
            lock = notes_lock(path)
            # fcntl is the base part's, run in this namespace: globals() names it where a linter reads this file alone.
            globals()['fcntl'].flock(lock, globals()['fcntl'].LOCK_EX)
            with open(path, encoding='utf-8') as f:
                lines = f.read().splitlines(keepends=True)
            at = next((i for i, x in enumerate(lines) if x.rstrip('\n') == body['line']), None)
            if at is None:  # filed, then dismissed from another page meanwhile: the issue is still the reply
                return self.reply(200, url) if url else self.reply(409, 'that note is no longer in the file; nothing was changed')
            del lines[at]
            with open(tmp, 'w', encoding='utf-8') as f:
                f.writelines(lines)
            os.chmod(tmp, os.stat(path).st_mode & 0o7777)
            os.replace(tmp, path)
        except (OSError, ValueError) as e:  # ValueError: a file that is not UTF-8
            try:
                os.remove(tmp)
            except OSError:
                pass
            return self.reply(500, '%sthe note could not be removed: %s' % (
                'filed as %s, but ' % url if url else '', getattr(e, 'strerror', None) or e))
        finally:
            if lock:
                lock.close()  # and with it the lock
        if url:
            return self.reply(200, url)
        print('dashboard: plugin problem dismissed by %s from %s in %s' % (user, self.client_address[0], path), file=sys.stderr, flush=True)
        self.reply(200, 'dismissed')

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
