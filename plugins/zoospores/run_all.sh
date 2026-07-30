#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Directory containing all configuration files.
CONFDIR="$(realpath "${1:-.}")"
[[ -d "$CONFDIR" ]] || {
    echo "Configuration directory not found: $CONFDIR" >&2
    exit 1
}

# Setting up Python environment
cd "$ROOT/setup"
./setup_python.sh "${2:-}"

# ------------------------------------------------------------------------------
# Analysing trajectories
# ------------------------------------------------------------------------------
cd "$ROOT/trajectory_analysis/metrics_extraction"
./extract_trajectory_metrics.sh \
    "$CONFDIR/extract_trajectory_metrics.conf"

cd "$ROOT/trajectory_analysis/metrics_analysis"
./analyse_trajectory_metrics.sh \
    "$CONFDIR/analyse_trajectory_metrics.conf"

cd "$ROOT/trajectory_analysis/plotting_overviews"
./plot_trajectory_overview.sh \
    "$CONFDIR/plot_trajectory_overview.conf"

# ------------------------------------------------------------------------------
# Model fitting
# ------------------------------------------------------------------------------
cd "$ROOT/model_fitting/hysteresis"
./analyse_hysteresis.sh \
    "$CONFDIR/analyse_hysteresis.conf"

cd "$ROOT/model_fitting/local_parameter_extraction"
./extract_local_parameters.sh \
    "$CONFDIR/extract_local_parameters.conf"

cd "$ROOT/model_fitting/hmm_model_fit"
./fit_and_interpret_zoospore_hmm.sh \
    "$CONFDIR/fit_and_interpret_zoospore_hmm.conf"

echo
echo "The analysis completed successfully."
echo "Configuration profile: $CONFDIR"
