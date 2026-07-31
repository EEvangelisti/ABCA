#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFDIR="$(realpath -e -- "${1:-.}")"
SETUP_CONFIG="${2:-}"

"$ROOT/setup/setup_python.sh" "$SETUP_CONFIG"
source "$ROOT/setup/python_venv/bin/activate"

scripts=(
    "$ROOT/trajectory_analysis/metrics_extraction/extract_trajectory_metrics.sh"
    "$ROOT/trajectory_analysis/metrics_analysis/analyse_trajectory_metrics.sh"
    "$ROOT/trajectory_analysis/plotting_overviews/plot_trajectory_overview.sh"
    "$ROOT/model_fitting/hysteresis/analyse_hysteresis.sh"
    "$ROOT/model_fitting/local_parameter_extraction/extract_local_parameters.sh"
    "$ROOT/model_fitting/hmm_model_fit/fit_and_interpret_zoospore_hmm.sh"
)

configs=(
    "$CONFDIR/extract_trajectory_metrics.conf"
    "$CONFDIR/analyse_trajectory_metrics.conf"
    "$CONFDIR/plot_trajectory_overview.conf"
    "$CONFDIR/analyse_hysteresis.conf"
    "$CONFDIR/extract_local_parameters.conf"
    "$CONFDIR/fit_and_interpret_zoospore_hmm.conf"
)

for i in "${!scripts[@]}"; do
    ABCA_CONFIG_DIR="$CONFDIR" "${scripts[$i]}" "${configs[$i]}"
done

echo
echo "The analysis completed successfully."
echo "Configuration profile: $CONFDIR"
