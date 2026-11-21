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
      failed tests;
      its container is named sweb.eval.<id>.conveyor-<run id>-<id>, which the run's end (swe.sh's swe_end) removes;
      exit 3 when the harness could not run the task (the task is not in the dataset, its image could not be
      fetched or built, or the run erred).
A dataset row holds the task's reference fix and hidden tests, and a card's sessions have a shell as this same
account: tasks and grade read the dataset into a cache folder of their own (private_cache()) and remove it when they
end or are stopped (SIGTERM or SIGHUP), so no copy of a row is on disk while a card builds.
"""
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile


# The swebench release this file is written for and that passed a check on the build machine, as swe.json pins it and
# docs/benchmarks.md installs it: swebench 5 has no MAP_REPO_VERSION_TO_SPECS, which tasks() reads.
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'swe.json')) as _f:
    SWEBENCH = json.load(_f)['swebench']


# '' when this Python's swebench is SWEBENCH, else the Board's text: no harness, or the one it has and what to install.
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
        return ''
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


# One kind of hidden test of the row (the names it lists) against the harness's report of the instance.
def tests_of(row, report, kind):
    names = json.loads(row[kind]) if isinstance(row[kind], str) else list(row[kind])
    ok = set(report.get('tests_status', {}).get(kind, {}).get('success', []))
    failed = [n for n in names if n not in ok]
    return {'passed': len(names) - len(failed), 'failed': len(failed), 'failedTests': failed}


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
        cache = private_cache()
        try:
            return (tasks(*a[1:]) or 0) if a[0] == 'tasks' else grade(*a[1:], cache)
        finally:
            shutil.rmtree(cache, ignore_errors=True)
    sys.stderr.write('usage: swe_harness.py check | tasks <dataset> <revision> <out> | image <image> | grade <dataset> <revision> <id> <patch> <folder> <run id>\n')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
