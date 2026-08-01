#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

# ------------------------------------------------------------------------------

PYTHON_COMMAND="${1:-/usr/bin/env python3}"
VENV_DIR="$ROOT/../python-scripts/zsp_venv"

read -r -a SYSTEM_PYTHON <<< "$PYTHON_COMMAND"

command -v "${SYSTEM_PYTHON[0]}" >/dev/null 2>&1 \
    || die "Python command not found: ${SYSTEM_PYTHON[0]}"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    printf 'Creating Python virtual environment...\n'
    "${SYSTEM_PYTHON[@]}" -m venv "$VENV_DIR"
fi

PYTHON="$VENV_DIR/bin/python"
require_executable "$PYTHON" "Python interpreter"

printf 'Upgrading pip...\n'
"$PYTHON" -m pip install --quiet --upgrade pip

printf 'Installing required packages...\n'
"$PYTHON" -m pip install --quiet --upgrade \
    numpy \
    pandas \
    scipy \
    matplotlib \
    scikit-learn \
    hmmlearn \
    tol-colors

job_done "Python successfully configured"
