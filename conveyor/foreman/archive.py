# SPDX-License-Identifier: Apache-2.0
"""archive.py <state.md> -- the Foreman's saved state kept small with no hand trim (foreman.sh start runs it).

Every item whose line starts `- DONE`, with its indented continuation lines, is appended to
state-archive-<YYYY-MM-DD>.md beside state.md under one timestamp line, then state.md is swapped in one step with a
temp file of the rest (renameat2 RENAME_EXCHANGE on Linux, renamex_np RENAME_SWAP on macOS). The archive is written
first: a kill between the two repeats an item, never loses one, and state.md is never absent.
A write to state.md is never lost, though no writer takes a lock. The temp file is written as .state.md.writing.*,
then renamed .state.md.archiving.<hash of the rest>.<hash of what was read>.<random> for the swap; once swapped, it
is renamed .state.md.before-archive.<hash of what it holds>.<random>. If state.md no longer holds what was read, it
is swapped back and the run fails, so the next run archives again. Every run checks both later names and fails
naming one whose content matches no hash in its name, so a write made through a descriptor opened before the swap
is reported, not dropped. Only its own run ever renames an .archiving file, and no run deletes one: deleting by
name could remove the file another run had just swapped in. A run deletes a matching .before-archive file, which no
run renames again, only under a Linux write lease, which the kernel grants only while no other descriptor is open on
the file and which holds back any new open until the delete; where no lease can be taken (another descriptor open,
or macOS), the file is left for a later run.
"""
import ctypes, fcntl, hashlib, os, sys, tempfile, time
path = sys.argv[1]
folder = os.path.dirname(os.path.abspath(path))
KEPT = ".state.md.before-archive."
SWAPPING = ".state.md.archiving."
WRITING = ".state.md.writing."
def read(name):
    with open(name, "rb") as f:
        return f.read()
def digest(body):
    return hashlib.sha256(body).hexdigest()[:16]
def kept_as(body):
    return KEPT + digest(body) + "."
for name in sorted(os.listdir(folder)):
    if name.startswith(SWAPPING):
        held = os.path.join(folder, name)
        try:
            body = read(held)
        except FileNotFoundError:
            continue
        if digest(body) not in name[len(SWAPPING):].split(".")[:2]:
            sys.exit(f"{held} was written while an archive run had it as state.md: once no archive run is going, copy what it holds into state.md, then delete it")
    elif name.startswith(KEPT):
        held = os.path.join(folder, name)
        fd = os.open(held, os.O_RDONLY)
        try:
            try:
                fcntl.fcntl(fd, fcntl.F_SETLEASE, fcntl.F_WRLCK)
                leased = True
            except (AttributeError, OSError):
                leased = False
            with os.fdopen(os.dup(fd), "rb") as f:
                body = f.read()
            if not name.startswith(kept_as(body)):
                sys.exit(f"{held} was written after it was swapped out of state.md: copy what it holds into state.md, then delete it")
            if leased:
                os.unlink(held)
        finally:
            os.close(fd)
libc = ctypes.CDLL(None, use_errno=True)
def swap(a, b):
    if sys.platform == "darwin":
        rc = libc.renamex_np(a.encode(), b.encode(), 2)
    else:
        rc = libc.renameat2(-100, a.encode(), -100, b.encode(), 2)
    if rc != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err), path)
seen = read(path)
kept, done, inside = [], [], False
for line in seen.splitlines(keepends=True):
    if line.startswith(b"- DONE"):
        inside = True
    elif not line.startswith((b" ", b"\t")):
        inside = False
    (done if inside else kept).append(line)
if not done:
    sys.exit(0)
if not done[-1].endswith(b"\n"):
    done[-1] += b"\n"
kept = b"".join(kept)
fd, tmp = tempfile.mkstemp(dir=folder, prefix=WRITING)
suffix = os.path.basename(tmp)[len(WRITING):]
swapped = False
try:
    with os.fdopen(fd, "wb") as f:
        f.write(kept)
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    # Named for the check only once whole, so a run checking it never reads a partial write.
    whole = os.path.join(folder, SWAPPING + digest(kept) + "." + digest(seen) + "." + suffix)
    os.rename(tmp, whole)
    tmp = whole
    if read(path) != seen:
        sys.exit("state.md changed while its DONE items were archived; left as it is")
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z").encode()
    with open(os.path.join(folder, time.strftime("state-archive-%Y-%m-%d.md")), "ab") as f:
        f.write(b"## Archived " + stamp + b" from state.md\n" + b"".join(done))
        f.flush()
        os.fsync(f.fileno())
    # Swapped, never replaced: whatever state.md was at that instant, even a file renamed onto it, is now at tmp.
    swap(tmp, path)
    swapped = True
    if read(tmp) == seen:
        os.rename(tmp, os.path.join(folder, kept_as(seen) + suffix))
    else:
        # Swapped back, tmp again holds the rest, unless a write reached it while it was state.md.
        swap(tmp, path)
        os.rename(tmp, os.path.join(folder, kept_as(kept) + suffix))
        sys.exit("state.md was written while its DONE items were archived; that write is back in state.md, so the next run archives them again")
finally:
    if not swapped and os.path.exists(tmp):
        os.unlink(tmp)
