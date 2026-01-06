#!/usr/bin/env bash
# Helper to run a sub-make target and tee its output to a log file
# Usage: run-submake.sh <target> <logfile> [extra-make-args...]
set -eu
target="$1"
logfile="$2"
shift 2 || true
export MAKEFLAGS
# Use pipefail so we capture make's exit status
set -o pipefail
make "$target" "$@" 2>&1 | tee "$logfile"
exit ${PIPESTATUS[0]:-0}
