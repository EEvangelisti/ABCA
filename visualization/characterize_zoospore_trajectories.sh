#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 trajectories.xml [options passed to characterize_zoospore_trajectories.py]" >&2
    echo "Example, real data:      $0 tracks.xml --dt 0.2217 --unit px" >&2
    echo "Example, simulation:     $0 simulated.xml --dt 0.1666667 --coord-scale 10 --unit um" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/plots"

python3 -m venv "${VENV_DIR}"
source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip
python -m pip install numpy matplotlib

python "${SCRIPT_DIR}/characterize_zoospore_trajectories.py" \
  --min-spots 50 \
  --max-spots 50 \
  --crop-mode random \
  --outdir "$(basename "$@" .xml)" \
  --random-seed 42 \
  "$@"

# --dt 0.0700506
# --unit micron

deactivate
