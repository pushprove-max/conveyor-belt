// SPDX-License-Identifier: Apache-2.0
// The seconds of each mocha test, for a card's test run of a project whose test command runs mocha (the pack's
// test.report, format mocha-times, setup.sh reportguess()): loaded in each node process of the run by
// NODE_OPTIONS=--require, so the test command and mocha's own output stay as they are. When mocha's runner runs
// tests, each test's end appends a line {"file": <its file>, "sec": <its seconds>} to the file CONVEYOR_MOCHA_REPORT
// names (tools/testreport.py reads it). A process that runs no mocha tests writes nothing.
'use strict';
const fs = require('fs');
const Module = require('module');

// reportask() gives the path in double quotes, as an option of NODE_OPTIONS takes it.
const out = (process.env.CONVEYOR_MOCHA_REPORT || '').replace(/^"(.*)"$/, '$1');
const load = Module._load;
let done = false;
if (out) {
  Module._load = function (request, parent, isMain) {
    const m = load.apply(this, arguments);
    if (!done && /(^|[\\/])runner(\.js)?$/.test(request) && m && m.prototype && typeof m.prototype.run === 'function') {
      let file = '';
      try { file = Module._resolveFilename(request, parent, isMain); } catch { /* not mocha's */ }
      if (/[\\/]mocha[\\/]lib[\\/]runner\.js$/.test(file)) {
        done = true;
        const run = m.prototype.run;
        // A parallel run's main process has a runner of its own run: only the workers, which run the tests, write.
        m.prototype.run = function (...args) {
          this.on('test end', (t) => {
            if (t && typeof t.file === 'string' && typeof t.duration === 'number') {
              try { fs.appendFileSync(out, JSON.stringify({ file: t.file, sec: t.duration / 1000 }) + '\n'); } catch { /* the run goes on */ }
            }
          });
          return run.apply(this, args);
        };
      }
    }
    return m;
  };
}
