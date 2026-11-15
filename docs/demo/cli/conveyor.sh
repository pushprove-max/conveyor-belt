#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The engine of the Claude Code beats' container (record-cli.sh puts it in place of conveyor/conveyor.sh, with the
# engine beside it as engine.sh): what the belt holds (snapshot, health, cards, history) and a retry are answered
# from the demo's timeline (mock.js ask), as is go (the tape starts the story clock); every other command by the
# engine itself.
here=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)
case ${1:-} in
  snapshot | health | cards | history | retry | go) exec node "$here/../docs/demo/cli/mock.js" ask "$@" ;;
  *) exec bash "$here/engine.sh" "$@" ;;
esac
