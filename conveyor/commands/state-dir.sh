# SPDX-License-Identifier: Apache-2.0
# `conveyor.sh state-dir`: the state folder (plan section 12): every reader outside the engine asks for it rather than
# assuming where it lies (ST, lib/paths.sh, which conveyor.sh loads). Sourced by conveyor.sh.
echo "$ST"
