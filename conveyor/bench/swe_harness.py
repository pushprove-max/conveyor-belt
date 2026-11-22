# SPDX-License-Identifier: Apache-2.0
"""The SWE-bench side of `conveyor.sh bench swe` (bench/swe.sh): the task list, each task's Docker image, and the
grade of a final patch by the official harness. It runs in a Python that has the swebench package at the release this file
is written for (SWEBENCH, which brings datasets) and a Docker it can use; swe.sh starts it with the swebench
virtualenv's Python (swe_h()). Nothing here builds a card.

Usage:
  swe_harness.py check
      exit 1, saying that this Python has no swebench or which one it has, when it is not SWEBENCH (bench/swe.sh's
      swe_setup runs it before a run or an arms check reads the task list, which a saved list would skip).
  swe_harness.py tasks <dataset> <revision> <out>
      every task of the dataset at that revision, one JSON line each, in the dataset's order, to <out>:
      {id, repo, url, base, issue, image, cmd}: no reference fix and no hidden test (cmd: the task's test command,
      run in a container of its image).
  swe_harness.py image <image>
      fetches the task's image; exit 3 when it cannot be fetched.
  swe_harness.py grade <dataset> <revision> <id> <patch file> <folder> <run id>
      grades the patch with the official harness (its run_evaluation, its Docker images, FAIL_TO_PASS and
      PASS_TO_PASS) in <folder>, given the task's own dataset row read again; prints {resolved, class, tests, ref,
      measures}: class is resolved, broke (every fail-to-pass test passes and a pass-to-pass test fails), partial
      (some fail-to-pass tests pass) or nofix (none); tests, each of failToPass and passToPass as {passed, failed,
      failedTests}, from the harness's report of the instance; ref, the size of the task's reference fix
      ({code, test}, each {files, added, removed}), and measures, those of the patch ({files, codeAdded, codeRemoved,
      testAdded, size: its code lines changed over the reference fix's, strays: it changes a code file the reference
      fix does not}); no text and no path of the reference fix or of a hidden test is in it, only the names of the
      failed tests; measures also has lintClean (ruff, at the release swe.json pins, with its default rules and no
      project settings, finds no problem in the files the patch changes that those files did not have at the base
      commit) and provesFix (the patch adds or changes a test file, and the test command on those files fails at the
      base commit with only the patch's test files, and passes with the whole patch), each null when it could not be
      measured; and clean (resolved, lintClean, size at most 2, no strays: false when one is false, null when none is
      false and one could not be measured);
      its container is named sweb.eval.<id>.conveyor-<run id>-<id>, which the run's end (swe.sh's swe_end) removes;
      exit 3 when the harness could not run the task (the task is not in the dataset, its image could not be
      fetched or built, or the run erred).
A dataset row holds the task's reference fix and hidden tests, and a card's sessions have a shell as this same
account: tasks and grade read the dataset into a cache folder of their own (private_cache()) and remove it when they
end or are stopped (SIGTERM or SIGHUP), so no copy of a row is on disk while a card builds. Each holds the machine's
dataset lock alone (dataset_lock()) while that folder is there, and no trial starts until it ends: a grade waits until
no trial, grade or task list read of any project on this machine holds the lock; tasks fails at once (a conveyor:
line) while one holds it.
"""
import fcntl
import glob
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

# The swebench release this file is written for and that passed a check on the build machine, as swe.json pins it and
# docs/benchmarks.md installs it: swebench 5 has no MAP_REPO_VERSION_TO_SPECS, which tasks() reads. RUFF is the ruff
# release that measures a patch's lint (lint_clean): another release has other rules.
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'swe.json')) as _f:
    _pins = json.load(_f)
SWEBENCH, RUFF = _pins['swebench'], _pins['ruff']


# A command's result, its output kept as text; its exit status is the caller's to read.
def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, check=False, **kw)


# The release of the ruff this Python runs as a module, or None when it has none.
def ruff_version():
    try:
        r = run([sys.executable, '-m', 'ruff', '--version'])
    except OSError:
        return None
    m = re.match(r'ruff (\S+)', r.stdout)
    return m.group(1) if r.returncode == 0 and m else None


# '' when this Python's swebench is SWEBENCH and its ruff is RUFF, else the Board's text: no harness, or the one it has
# and what to install.
def swebench_wrong():
    try:
        import swebench
    except ImportError:
        return 'The build machine has no SWE benchmark harness. Install it in the benchmark virtual environment, then check again.'
    # The package's own __version__ first: a swebench on PYTHONPATH need not be the one pip recorded.
    v = getattr(swebench, '__version__', None)
    if not v:
        try:
            from importlib.metadata import version
            v = version('swebench')
        except Exception:
            v = None
    if v == SWEBENCH:
        r = ruff_version()
        has = f'ruff {r}' if r else 'no ruff'
        return '' if r == RUFF else f'The build machine has {has}. This benchmark needs ruff {RUFF}. Install ruff {RUFF} in the benchmark virtual environment, then check again.'
    need = 'swebench %s' % SWEBENCH
    return ('The build machine has harness %s. This benchmark needs %s. Install %s in the benchmark virtual environment, then check again.'
            % ('swebench %s' % v if v else 'swebench of no known version', need, need))


def image_of(instance):
    # The harness's prebuilt evaluation image on Docker Hub (namespace swebench).
    return 'swebench/sweb.eval.x86_64.%s:latest' % instance.lower().replace('__', '_1776_')


# A new folder as Hugging Face's whole cache (the dataset's download and its rows), for this process and the official
# harness it starts; the caller removes it.
def private_cache():
    d = tempfile.mkdtemp(prefix='conveyor-swe-')
    os.environ['HF_HOME'] = d
    for k in ('HF_DATASETS_CACHE', 'HF_HUB_CACHE', 'HUGGINGFACE_HUB_CACHE', 'HF_XET_CACHE', 'HF_ASSETS_CACHE'):
        os.environ.pop(k, None)
    return d


# The machine's dataset lock file, its folder made: bench/swe_arms.sh's SWE_DSLOCK, the same file beside the host
# file, which each trial holds shared.
def dataset_lock():
    d = os.path.join(os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config'), 'conveyor', 'machine')
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, 'swe-dataset.lock')


def tasks(dataset, revision, out):
    try:
        from swebench.harness.constants import MAP_REPO_VERSION_TO_SPECS
    except ImportError:
        raise SystemExit('conveyor: ' + (swebench_wrong()
                                         or 'the SWE-bench harness has swebench %s with no MAP_REPO_VERSION_TO_SPECS' % SWEBENCH))
    from datasets import load_dataset
    rows = load_dataset(dataset, split='test', revision=revision)
    with open(out, 'w') as f:
        for r in rows:
            cmd = MAP_REPO_VERSION_TO_SPECS[r['repo']][r['version']]['test_cmd']
            if isinstance(cmd, list):
                cmd = ' && '.join(cmd)
            image = image_of(r['instance_id'])
            # The repo's test command, run in the task's own environment (env: the image's Python with the task's
            # packages): inside a container of its image (every arm builds the task in one, bench/swe_arms.sh), in
            # the folder the command starts in.
            env = 'source /opt/miniconda3/bin/activate && conda activate testbed'
            test = env + ' && ' + cmd
            f.write(json.dumps({'id': r['instance_id'], 'repo': r['repo'], 'url': 'https://github.com/%s.git' % r['repo'],
                                'base': r['base_commit'], 'issue': r['problem_statement'], 'image': image, 'env': env, 'cmd': test}) + '\n')


def image(name):
    return 0 if subprocess.run(['docker', 'pull', '-q', name], stdout=subprocess.DEVNULL).returncode == 0 else 3


# A file the task's test command (pytest, or Django's runner) takes as a test: under a tests or test folder, or named
# test_*.py, *_test.py or conftest.py.
def is_test(path):
    name = path.rsplit('/', 1)[-1]
    return bool(re.search(r'(^|/)tests?/', path)) or name.startswith('test_') or name.endswith('_test.py') or name == 'conftest.py'


# {path: [lines added, lines removed]} of a git diff: the lines of each hunk are counted by the hunk's own header, so
# a removed line that starts with "--" is not read as a file header.
def diff_files(text):
    files, cur, old, new = {}, None, 0, 0
    for line in text.split('\n'):
        if old > 0 or new > 0:
            if line.startswith('+'):
                files[cur][0] += 1
                new -= 1
            elif line.startswith('-'):
                files[cur][1] += 1
                old -= 1
            elif not line.startswith('\\'):
                old -= 1
                new -= 1
            continue
        m = re.match(r'diff --git a/.* b/(.*)$', line)
        if m:
            cur = m.group(1)
            files.setdefault(cur, [0, 0])
            continue
        m = re.match(r'@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@', line)
        if m and cur is not None:
            old = 1 if m.group(1) is None else int(m.group(1))
            new = 1 if m.group(2) is None else int(m.group(2))
    return files


# The size of a diff's files, split into code and test files.
def diff_size(files):
    r = {k: {'files': 0, 'added': 0, 'removed': 0} for k in ('code', 'test')}
    for path, (a, d) in files.items():
        s = r['test' if is_test(path) else 'code']
        s['files'] += 1
        s['added'] += a
        s['removed'] += d
    return r


# The patch's measures against the reference fix's, from the two diffs: only counts and the one flag, no path.
def measures(patch, fix):
    mine, ref = diff_files(patch), diff_files(fix)
    size, rsize = diff_size(mine), diff_size(ref)
    rcode = rsize['code']['added'] + rsize['code']['removed']
    return rsize, {'files': len(mine), 'codeAdded': size['code']['added'], 'codeRemoved': size['code']['removed'],
                   'testAdded': size['test']['added'],
                   'size': round((size['code']['added'] + size['code']['removed']) / rcode, 2) if rcode else None,
                   'strays': any(not is_test(p) and p not in ref for p in mine)}


# Whether the patch is clean: resolved, lint clean, at most twice the reference fix's size, and no strays. False as soon
# as one of them is false, else None (not known) when one could not be measured (lintClean, or a size when the reference
# fix changes no code line), else True.
def is_clean(resolved, m):
    parts = [resolved, m['lintClean'], None if m['size'] is None else m['size'] <= 2, not m['strays']]
    return False if any(p is False for p in parts) else None if any(p is None for p in parts) else True


# One kind of hidden test of the row (the names it lists) against the harness's report of the instance.
def tests_of(row, report, kind):
    names = json.loads(row[kind]) if isinstance(row[kind], str) else list(row[kind])
    ok = set(report.get('tests_status', {}).get(kind, {}).get('success', []))
    failed = [n for n in names if n not in ok]
    return {'passed': len(names) - len(failed), 'failed': len(failed), 'failedTests': failed}


# Django's runner takes a test module, not a file: tests/a/b.py is a.b.
def test_label(repo, path):
    return re.sub(r'\.py$', '', re.sub(r'^tests/', '', path)).replace('/', '.') if repo == 'django/django' else path


# What ruff finds in <paths> of <folder>, as {(path, rule, message): count}: its default rules and no project settings,
# so that two folders compare by what they hold, not by a config. It runs in <cwd>, not in <folder>: python puts its
# working folder first on the module path, and a patch that adds ruff.py would run its code as ruff.
def ruff_findings(folder, paths, cwd):
    if not paths:
        return {}
    r = run([sys.executable, '-m', 'ruff', 'check', '--isolated', '--no-cache', '--output-format', 'json']
            + [os.path.join(os.path.realpath(folder), p) for p in paths], cwd=cwd)
    found = {}
    for x in json.loads(r.stdout):
        k = (os.path.relpath(x['filename'], os.path.realpath(folder)), x['code'], x['message'])
        found[k] = found.get(k, 0) + 1
    return found


# True when ruff finds nothing in the patch's python files that those files did not have at the base commit (a line
# that moved is not new; a file the patch adds starts with nothing). None when it could not be measured.
def lint_clean(box, patch, py, cache):
    before, after = tempfile.mkdtemp(prefix='before', dir=cache), tempfile.mkdtemp(prefix='after', dir=cache)
    for p in py:
        os.makedirs(os.path.dirname(os.path.join(before, p)), exist_ok=True)
        os.makedirs(os.path.dirname(os.path.join(after, p)), exist_ok=True)
        if run(['docker', 'cp', f'{box}:/testbed/{p}', os.path.join(before, p)]).returncode == 0:
            shutil.copy(os.path.join(before, p), os.path.join(after, p))
    if run(['git', 'apply', '--include=*.py', patch], cwd=after).returncode != 0:
        return None
    old = ruff_findings(before, [p for p in py if os.path.exists(os.path.join(before, p))], cache)
    new = ruff_findings(after, [p for p in py if os.path.exists(os.path.join(after, p))], cache)
    return all(n <= old.get(k, 0) for k, n in new.items())


# True when the test command on the patch's test files fails at the base commit with only those files of the patch, and
# passes with the whole patch. False when the patch has no such test file. None when it could not be measured.
def proves_fix(box, patch, row, tests):
    if not tests:
        return False
    from swebench.harness.constants import MAP_REPO_VERSION_TO_SPECS
    cmd = MAP_REPO_VERSION_TO_SPECS[row['repo']][row['version']]['test_cmd']
    cmd = 'source /opt/miniconda3/bin/activate && conda activate testbed && ' + (' && '.join(cmd) if isinstance(cmd, list) else cmd)
    if run(['docker', 'cp', patch, f'{box}:/tmp/conveyor.patch']).returncode != 0:
        return None
    labels = ' '.join(shlex.quote(test_label(row['repo'], p)) for p in tests)
    rcs = []
    for flag in ('--include', '--exclude'):
        apply = 'git apply ' + ' '.join(f'{flag}={shlex.quote(p)}' for p in tests) + ' /tmp/conveyor.patch'
        a = run(['docker', 'exec', '-w', '/testbed', box, 'bash', '-c', apply])
        t = run(['docker', 'exec', '-w', '/testbed', box, 'bash', '-c', f'{cmd} {labels}'], timeout=1800)
        # 125 to 127: docker, or the shell, could not run the command: not a test that failed.
        if a.returncode != 0 or t.returncode in (125, 126, 127):
            return None
        rcs.append(t.returncode)
    return rcs[0] != 0 and rcs[1] == 0


# The patch's lintClean and provesFix, measured in a container of the task's image (the base commit is in /testbed),
# named box so that the run's end removes it when this process is stopped.
def checks(row, patch, image, box, cache):
    with open(patch) as f:
        files = diff_files(f.read())
    py = [p for p in files if p.endswith('.py')]
    out = {'lintClean': True, 'provesFix': False}
    if not py:
        return out
    tests = [p for p in py if is_test(p) and files[p][0] > 0]

    # Each is None when its own step failed: Docker, ruff, git, or a command that ran out of time.
    def measured(f, *a):
        try:
            return f(box, patch, *a)
        except (OSError, subprocess.SubprocessError, ValueError, KeyError, ImportError):
            return None
    try:
        if run(['docker', 'run', '-d', '--name', box, image, 'sleep', 'infinity']).returncode != 0:
            return {'lintClean': None, 'provesFix': None}
        return {'lintClean': measured(lint_clean, py, cache), 'provesFix': measured(proves_fix, row, tests)}
    except OSError:
        return {'lintClean': None, 'provesFix': None}
    finally:
        try:
            run(['docker', 'rm', '-f', box])
        except OSError:
            pass


def grade(dataset, revision, instance, patch, folder, run, cache):
    from datasets import load_dataset
    rows = [dict(r) for r in load_dataset(dataset, split='test', revision=revision) if r['instance_id'] == instance]
    if not rows:
        return 3
    # The official harness loads a local dataset only from a file named .json, .jsonl or .parquet.
    raw = os.path.join(cache, 'task.jsonl')
    with open(raw, 'w') as f:
        f.write(json.dumps(rows[0]) + '\n')
    os.makedirs(folder, exist_ok=True)
    preds = os.path.join(folder, 'preds.jsonl')
    with open(patch) as p, open(preds, 'w') as f:
        f.write(json.dumps({'instance_id': instance, 'model_name_or_path': 'conveyor', 'model_patch': p.read()}) + '\n')
    # The harness names its container sweb.eval.<instance>.<run_id>: the run's ID in it lets a Stopped run remove it.
    run_id = 'conveyor-%s-%s' % (run, instance)
    rc = subprocess.run([sys.executable, '-m', 'swebench.harness.run_evaluation', '--dataset_name', raw, '--predictions_path', preds,
                         '--instance_ids', instance, '--run_id', run_id, '--max_workers', '1', '--namespace', 'swebench'],
                        cwd=folder, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    reports = glob.glob(os.path.join(folder, '*.%s.json' % run_id))
    if rc != 0 or not reports:
        return 3
    with open(reports[0]) as f:
        r = json.load(f)
    if instance in r.get('error_ids', []):
        return 3
    # The harness's report of the instance: the tests that passed, in the folder it ran in.
    found = glob.glob(os.path.join(folder, 'logs', 'run_evaluation', run_id, '*', instance, 'report.json'))
    if not found:
        return 3
    with open(found[0]) as f:
        report = json.load(f).get(instance, {})
    resolved = instance in r.get('resolved_ids', [])
    f2p, p2p = tests_of(rows[0], report, 'FAIL_TO_PASS'), tests_of(rows[0], report, 'PASS_TO_PASS')
    with open(patch) as f:
        ref, mine = measures(f.read(), rows[0]['patch'])
    mine.update(checks(rows[0], patch, image_of(instance), f'sweb.eval.{instance}.{run_id}-check', cache))
    mine['clean'] = is_clean(resolved, mine)
    cls = ('resolved' if resolved else 'broke' if f2p['failed'] == 0 else 'partial' if f2p['passed'] > 0 else 'nofix')
    print(json.dumps({'resolved': resolved, 'class': cls, 'tests': {'failToPass': f2p, 'passToPass': p2p}, 'ref': ref, 'measures': mine}))
    return 0


def main(a):
    if a == ['check']:
        w = swebench_wrong()
        if w:
            print(w)
        return 1 if w else 0
    if len(a) == 2 and a[0] == 'image':
        return image(a[1])
    if (len(a) == 4 and a[0] == 'tasks') or (len(a) == 7 and a[0] == 'grade'):
        # `bench swe stop` ends the run with SIGTERM: exit through the finally below, so the cache is removed then too.
        for s in (signal.SIGTERM, signal.SIGHUP):
            signal.signal(s, lambda n, _: sys.exit(128 + n))
        # Held alone while the cache is there: a grade waits until no trial, grade or task list read holds it. tasks
        # does not wait: a run's Start reads the task list before the run is recorded, so a wait for a trial of hours
        # would outlast the Board's Start and leave no run for Stop to end. The lock does not say which of the three
        # holds it, so the refusal names all three.
        with open(dataset_lock(), 'a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | (fcntl.LOCK_NB if a[0] == 'tasks' else 0))
            except BlockingIOError:
                sys.stderr.write('conveyor: a SWE-bench trial, grade or task list read on this machine uses the dataset, so the task list cannot be read now: start again when it ends\n')
                return 1
            cache = private_cache()
            try:
                return (tasks(*a[1:]) or 0) if a[0] == 'tasks' else grade(*a[1:], cache)
            finally:
                # A signal now would raise inside rmtree and leave the rows on disk: the process ends once they are gone.
                for s in (signal.SIGTERM, signal.SIGHUP):
                    signal.signal(s, signal.SIG_IGN)
                shutil.rmtree(cache, ignore_errors=True)
    sys.stderr.write('usage: swe_harness.py check | tasks <dataset> <revision> <out> | image <image> | grade <dataset> <revision> <id> <patch> <folder> <run id>\n')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
