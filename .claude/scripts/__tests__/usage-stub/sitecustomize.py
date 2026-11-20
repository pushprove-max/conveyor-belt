# SPDX-License-Identifier: Apache-2.0
# Claude's usage endpoint, stubbed for the tests of its readers: a folder put on PYTHONPATH, so a reader run as it runs
# for real (dashboard.sh, the engine's guard, the Foreman's watcher) asks this stub, and nothing leaves the box.
# Each ask is one line in $USAGE_STUB_LOG. The answer is the words of $USAGE_STUB_ANSWER: "429 <Retry-After>", or
# "<utilization> <resets_at>". Any other address, and any process with no USAGE_STUB_ANSWER, goes to the real urlopen.
import io
import json
import os
import urllib.error
import urllib.request
from email.message import Message

_real = urllib.request.urlopen


def _urlopen(req, *a, **k):
    url = getattr(req, "full_url", req)
    if url != "https://api.anthropic.com/api/oauth/usage" or not os.environ.get("USAGE_STUB_ANSWER"):
        return _real(req, *a, **k)
    with open(os.environ["USAGE_STUB_LOG"], "a") as f:
        f.write("asked\n")
    with open(os.environ["USAGE_STUB_ANSWER"]) as f:
        ans = f.read().split()
    if ans[0] == "429":
        m = Message()
        m["Retry-After"] = ans[1]
        raise urllib.error.HTTPError(url, 429, "Too Many Requests", m, None)
    return io.BytesIO(json.dumps({"seven_day": {"utilization": float(ans[0]), "resets_at": ans[1] if len(ans) > 1 else None}}).encode())


urllib.request.urlopen = _urlopen
