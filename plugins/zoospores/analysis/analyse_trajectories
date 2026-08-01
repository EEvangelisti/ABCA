#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFDIR="$(realpath -- "${1:-.}")"

"$ROOT/run.sh" extract "$CONFDIR"

export SKIP_PYTHON_SETUP=1

"$ROOT/run.sh" analyse "$CONFDIR"
"$ROOT/run.sh" plot "$CONFDIR"
