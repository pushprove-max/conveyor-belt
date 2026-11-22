# SPDX-License-Identifier: Apache-2.0
# A part of dashboard_server.py, run in its namespace (run_part()), not a module of its own: the login store, the
# trusted devices, the passwords and MFA, the user actions, the cookies, the certificate, the command line's actions
# and the sessions.


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


def is_admin(name):
    """Whether a logged-in name is an admin, by the store as it is now."""
    return role_of(read_store(), name) == 'admin'


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
