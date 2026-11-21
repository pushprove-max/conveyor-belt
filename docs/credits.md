# Credits

Conveyor ships a copy of these works. The repository holds each one's licence text, and [NOTICE](../NOTICE) lists
them:

- [STE80 Humanizer](https://github.com/Dodaios/ste80-humanizer) by Dodaios, MIT licence (`conveyor/rules/ste80-LICENSE`):
  the writing rules for the Board's texts, the engine's reason texts and these pages, a pinned copy in
  `conveyor/rules/ste80.md`. Its Pass 1 is adapted from [humanizer](https://github.com/blader/humanizer) by Siqi Chen,
  MIT licence, in the same licence file.
- [three.js](https://threejs.org) by the three.js authors, MIT licence (`.claude/dashboard/vendor/three/LICENSE`): the
  Board's 3D belt view, a copy in `.claude/dashboard/vendor/three/`.

Conveyor features are built on these works, which Conveyor does not copy:

- [Matt Pocock's skills](https://github.com/mattpocock/skills) (`mattpocock-skills`) by Matt Pocock, MIT licence: the
  plan command recommends skills from this plugin.
- [Claude Code](https://github.com/anthropics/claude-code) by Anthropic, Anthropic's commercial terms: it runs the
  builder, reviewer and Foreman sessions.
- [Codex CLI](https://github.com/openai/codex) by OpenAI, Apache-2.0 licence: the Codex reviewer and builder models.
- [OpenCode](https://github.com/sst/opencode) by SST, MIT licence: the OpenCode models.
- [jq](https://github.com/jqlang/jq) by Stephen Dolan and the jq contributors, MIT licence: the engine reads and
  writes all its JSON with it.
- [gitleaks](https://github.com/gitleaks/gitleaks) by Zachary Rice, MIT licence: `conveyor/tools/history-scan.sh`
  finds secrets in the history with it.
- [git filter-repo](https://github.com/newren/git-filter-repo) by Elijah Newren, MIT licence:
  `conveyor/tools/history-rewrite.sh` rewrites the history with it.
- The Board's Python packages, from `.claude/scripts/requirements.txt`:
  - [`pyotp`](https://github.com/pyauth/pyotp) by PyAuth, MIT licence, for the TOTP codes.
  - [`segno`](https://github.com/heuer/segno) by Lars Heuer, BSD-3-Clause licence, for the enrolment QR code.
  - [`cryptography`](https://github.com/pyca/cryptography) by the Python Cryptographic Authority, Apache-2.0 or
    BSD-3-Clause licence, for the TOTP secret encrypted at rest. Its own dependencies are
    [`cffi`](https://github.com/python-cffi/cffi) by the CFFI authors, MIT licence, and
    [`pycparser`](https://github.com/eliben/pycparser) by Eli Bendersky, BSD-3-Clause licence.
- The npm packages, from `package.json`:
  - [`jsdom`](https://github.com/jsdom/jsdom) by the jsdom contributors, MIT licence, renders the Board's page in its
    view tests.
  - [`typescript`](https://github.com/microsoft/TypeScript) by Microsoft, Apache-2.0 licence: its parser reads test
    files for the new-test-file hook (`.claude/hooks/new-test-file-guard.sh`).
  - [`eslint`](https://github.com/eslint/eslint) by the ESLint contributors, MIT licence, checks the Board's
    JavaScript in the lint step (`.conveyor/lint-js.sh`).
  - [`@eslint/js`](https://github.com/eslint/eslint/tree/main/packages/js) by the ESLint contributors, MIT licence,
    gives the ESLint configuration (`eslint.config.js`) its recommended rules.
- The demo's npm packages, from `docs/demo/package.json`:
  - [`hyperframes`](https://github.com/heygen-com/hyperframes) by HeyGen, Apache-2.0 licence, renders the demo to
    video.
  - [`puppeteer`](https://github.com/puppeteer/puppeteer) by the Chrome DevTools authors, Apache-2.0 licence, with its
    own headless Chrome, captures the Board for it.
