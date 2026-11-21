# SPDX-License-Identifier: Apache-2.0
# A part of dashboard_server.py, run in its namespace (run_part()), not a module of its own: the page server's
# request handler, Handler: its class settings and the second half of its methods (the first half is Pages,
# dashboard_server_pages.py): POST /control and /machine, the routes of GET and POST, the users, the reads the page
# asks for and the live feed.


class Handler(Pages, http.server.SimpleHTTPRequestHandler):
    timeout = 30  # a client that stalls (or never finishes the TLS handshake) frees its thread
    # A browser runs a module (Belt 3D's three.js, vendor/three/) only with a JavaScript type, whatever the system's
    # own table of types says.
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, '.js': 'text/javascript'}
    # A browser keeps its connection for the page's next file, so the first load is not a TLS handshake a file. Every
    # reply so has a Content-Length; the /events stream, which has none, says Connection: close and closes.
    protocol_version = 'HTTP/1.1'

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
        # A judge replay's run calls the judge with the host's model account once a review: an admin's. Its estimate calls no model.
        if not machine and body['action'] == 'replay' and body['args'][-1] != '--estimate' and role_of(read_store(), user) != 'admin':
            return self.reply(403, 'only an admin runs a judge replay')
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
            # A dismiss or a filed issue changes the history where the live feed's ledger key may not show it: the next
            # GET /history builds it again.
            drop_history_key(self.directory)
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
        # Compare's answer is the whole comparison (totals, the tasks, each flipped task's facts); a Start's and a check's
        # is every line of their receipt, or of their end when it came first; the ruling row keeps its last line.
        whole = action == 'bench' and (args[:1] in (['diff'], ['run']) or args[:2] == ['arms', 'check'])
        answer = run.stdout.strip() if results is None and whole and run.stdout.strip() else said
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
        newest the snapshot keeps: dashboard.sh --history's JSON, which reads the host again only when the ledger
        changed. Its kept copy, while that script would print it, is served from the file with no process
        (kept_history). One build at a time per served folder: a second ask waits for it and gets the copy it kept.
        The ETag is that of the key and the copy, and an If-None-Match that names it is a 304. The page asks for it
        while one of those panels is shown. 502 with the reason when it gives none."""
        if not self.authed():
            return self.reply(401, 'log in to see the history')
        kept = kept_history(self.directory)
        if kept is None:
            lock, drops = history_lock(self.directory)
            with lock:
                kept = kept_history(self.directory)  # one built while this ask waited
                if kept is None:
                    drops = history_lock(self.directory)[1]
                    try:
                        run = run_script(['bash', os.path.join(HERE, 'dashboard.sh'), '--history'], HISTORY_LIMIT)
                    except subprocess.TimeoutExpired:
                        return self.reply(502, 'the history did not come in %d s' % HISTORY_LIMIT)
                    except OSError as e:
                        return self.reply(502, 'could not start dashboard.sh: %s' % e)
                    if run.returncode != 0:
                        return self.reply(502, (run.stderr.strip().splitlines() or ['no message'])[-1])
                    if history_lock(self.directory)[1] != drops:  # an action taken while it ran: its copy may be from before
                        drop_history_key(self.directory)
                    # The copy as kept, with its ETag; its own output, with none, when it was dropped or the feed moved.
                    kept = kept_history(self.directory) or (run.stdout.encode(), None)
        body, self.tag = kept  # end_headers sends the tag, with Cache-Control no-cache
        if self.tag and etag_matches(self.headers.get('If-None-Match'), self.tag):
            self.send_response(304)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
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
        if self.path in ('/plugin-dismiss', '/plugin-preview', '/plugin-file'):
            return self.plugin_note(self.path[len('/plugin-'):])
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
