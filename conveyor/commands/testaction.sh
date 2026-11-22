# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh testaction <judge | explain | run> <test file> | testaction stop <id>`: a session of the Tests seat about
# one test file, a run of one test file, or the stop of one (testaction(), lib/testaction.sh); and `conveyor.sh
# testissue <test file> <title> <body>`, an issue about one test file filed from the Board's Tests page (testissue(),
# the same file); `conveyor.sh cardissue <card id>`, the Board's File on GitHub on a landed card with no GitHub issue
# (cardissue(), the same file); `conveyor.sh card [--release <version>] <title> <body>`, a card the Foreman's owner ordered (cardnew(), the same file); and `conveyor.sh mutate <test file>`, a mutation check of one test file (mutate(), lib/mutate.sh).
# Each runs the function of its name. Sourced by conveyor.sh.
. "$HERE/lib/slots.sh" || exit 1
. "$HERE/lib/prompts.sh" || exit 1
. "$HERE/lib/control.sh" || exit 1
. "$HERE/lib/views.sh" || exit 1
. "$HERE/lib/issues.sh" || exit 1
. "$HERE/lib/pick.sh" || exit 1
. "$HERE/lib/session.sh" || exit 1
. "$HERE/lib/review.sh" || exit 1
. "$HERE/lib/testrun.sh" || exit 1
. "$HERE/lib/claim.sh" || exit 1
. "$HERE/lib/push.sh" || exit 1
. "$HERE/lib/followups.sh" || exit 1
. "$HERE/lib/flaky.sh" || exit 1
. "$HERE/lib/testaction.sh" || exit 1
. "$HERE/lib/testfiles.sh" || exit 1
. "$HERE/lib/mutate.sh" || exit 1
. "$HERE/lib/testrules.sh" || exit 1
. "$HERE/lib/survey.sh" || exit 1
. "$HERE/lib/card.sh" || exit 1
. "$HERE/lib/lane.sh" || exit 1
. "$HERE/lib/run.sh" || exit 1
. "$HERE/lib/machine.sh" || exit 1
. "$HERE/lib/install.sh" || exit 1
names || exit 1
case $1 in testaction) shift; testaction "$@" ;; testissue) shift; testissue "$@" ;; card) shift; cardnew "$@" ;; cardissue) shift; cardissue "$@" ;; mutate) shift; mutate "$@" ;; esac
