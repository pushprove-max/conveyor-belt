# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh watch`: the stream: a snapshot, then one line per change, from file notifications (watch.py says what
# each holds). Its paths are lib/paths.sh's, which conveyor.sh loads. Sourced by conveyor.sh.
exec python3 "$HERE/watch.py" "${STATE%/*}" "$CARDS" "$MAIN"
