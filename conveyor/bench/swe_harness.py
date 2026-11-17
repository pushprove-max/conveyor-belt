# SPDX-License-Identifier: Apache-2.0
"""The SWE-bench side of `conveyor.sh bench swe` (bench/swe.sh): the task list, each task's Docker image, and the
grade of a final patch by the official harness. It runs in a Python that has the swebench package (pip install
swebench, which brings datasets) and a Docker it can use; swe.sh starts it with the swebench virtualenv's Python
(swe_h()). Nothing here builds a card.

Usage:
  swe_harness.py tasks <dataset> <revision> <out>
      every task of the dataset at that revision, one JSON line each, in the dataset's order, to <out>:
      {id, repo, url, base, issue, image, test}; the dataset's own rows to <out>.jsonl (what grade reads: the
      official harness loads a local dataset only from a file named .json, .jsonl or .parquet).
  swe_harness.py image <image>
      fetches the task's image; exit 3 when it cannot be fetched.
  swe_harness.py grade <raw dataset> <id> <patch file> <folder>
      grades the patch with the official harness (its run_evaluation, its Docker images, FAIL_TO_PASS and
      PASS_TO_PASS) in <folder>; prints {"resolved": true|false}; exit 3 when the harness could not run the task
      (its image could not be fetched or built, or the run erred).
"""
import glob
import json
import os
import shlex
import subprocess
import sys


def image_of(instance):
    # The harness's prebuilt evaluation image on Docker Hub (namespace swebench).
    return 'swebench/sweb.eval.x86_64.%s:latest' % instance.lower().replace('__', '_1776_')


def tasks(dataset, revision, out):
    from datasets import load_dataset
    from swebench.harness.constants import MAP_REPO_VERSION_TO_SPECS
    rows = load_dataset(dataset, split='test', revision=revision)
    with open(out, 'w') as f, open(out + '.jsonl', 'w') as raw:
        for r in rows:
            raw.write(json.dumps(dict(r)) + '\n')
            cmd = MAP_REPO_VERSION_TO_SPECS[r['repo']][r['version']]['test_cmd']
            if isinstance(cmd, list):
                cmd = ' && '.join(cmd)
            image = image_of(r['instance_id'])
            # The repo's test command, run in the task's own environment: its image, the worktree as /testbed.
            test = ('docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$(pwd -P):/testbed" -w /testbed %s '
                    '/bin/bash -c %s' % (image, shlex.quote('source /opt/miniconda3/bin/activate && conda activate testbed && ' + cmd)))
            f.write(json.dumps({'id': r['instance_id'], 'repo': r['repo'], 'url': 'https://github.com/%s.git' % r['repo'],
                                'base': r['base_commit'], 'issue': r['problem_statement'], 'image': image, 'test': test}) + '\n')


def image(name):
    return 0 if subprocess.run(['docker', 'pull', '-q', name], stdout=subprocess.DEVNULL).returncode == 0 else 3


def grade(raw, instance, patch, folder):
    os.makedirs(folder, exist_ok=True)
    preds = os.path.join(folder, 'preds.jsonl')
    with open(patch) as p, open(preds, 'w') as f:
        f.write(json.dumps({'instance_id': instance, 'model_name_or_path': 'conveyor', 'model_patch': p.read()}) + '\n')
    run_id = 'conveyor-' + instance
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
    print(json.dumps({'resolved': instance in r.get('resolved_ids', [])}))
    return 0


def main(a):
    if len(a) == 4 and a[0] == 'tasks':
        return tasks(*a[1:]) or 0
    if len(a) == 2 and a[0] == 'image':
        return image(a[1])
    if len(a) == 5 and a[0] == 'grade':
        return grade(*a[1:])
    sys.stderr.write('usage: swe_harness.py tasks <dataset> <revision> <out> | image <image> | grade <raw> <id> <patch> <folder>\n')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
