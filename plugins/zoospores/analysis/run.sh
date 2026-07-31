#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat >&2 <<'EOF'
Usage:
  ./run.sh COMMAND CONFDIR [SETUP_CONFIG]

Available commands:
  extract_trajectory_metrics
  analyse_trajectory_metrics
  plot_trajectory_overview
  analyse_hysteresis
  extract_local_parameters
  fit_and_interpret_zoospore_hmm
  model_comparison
  simulation_validation
  trajectory_resampling

Examples:
  ./run.sh extract_trajectory_metrics configurations/p_nicotianae
  ./run.sh model_comparison configurations/default
  ./run.sh simulation_validation configurations/default
  ./run.sh trajectory_resampling configurations/default
EOF
}

if (( $# < 2 || $# > 3 )); then
    usage
    exit 2
fi

COMMAND="$1"
CONFDIR="$(realpath -e -- "$2")"
SETUP_CONFIG="${3:-}"

[[ -d "$CONFDIR" ]] || {
    echo "Error: configuration directory not found: $CONFDIR" >&2
    exit 1
}

case "$COMMAND" in
    extract_trajectory_metrics)
        SCRIPT="$ROOT/trajectory_analysis/metrics_extraction/extract_trajectory_metrics.sh"
        CONFIG="$CONFDIR/extract_trajectory_metrics.conf"
        ;;

    analyse_trajectory_metrics)
        SCRIPT="$ROOT/trajectory_analysis/metrics_analysis/analyse_trajectory_metrics.sh"
        CONFIG="$CONFDIR/analyse_trajectory_metrics.conf"
        ;;

    plot_trajectory_overview)
        SCRIPT="$ROOT/trajectory_analysis/plotting_overviews/plot_trajectory_overview.sh"
        CONFIG="$CONFDIR/plot_trajectory_overview.conf"
        ;;

    analyse_hysteresis)
        SCRIPT="$ROOT/model_fitting/hysteresis/analyse_hysteresis.sh"
        CONFIG="$CONFDIR/analyse_hysteresis.conf"
        ;;

    extract_local_parameters)
        SCRIPT="$ROOT/model_fitting/local_parameter_extraction/extract_local_parameters.sh"
        CONFIG="$CONFDIR/extract_local_parameters.conf"
        ;;

    fit_and_interpret_zoospore_hmm)
        SCRIPT="$ROOT/model_fitting/hmm_model_fit/fit_and_interpret_zoospore_hmm.sh"
        CONFIG="$CONFDIR/fit_and_interpret_zoospore_hmm.conf"
        ;;

    model_comparison)
        SCRIPT="$ROOT/model_validation/model_comparison/compare_models.sh"
        CONFIG="$CONFDIR/compare_models.conf"
        ;;

    simulation_validation)
        SCRIPT="$ROOT/model_validation/simulation_validation/validate_simulations.sh"
        CONFIG="$CONFDIR/validate_simulations.conf"
        ;;

    trajectory_resampling)
        SCRIPT="$ROOT/model_validation/trajectory_resampling/resample_trajectories.sh"
        CONFIG="$CONFDIR/resample_trajectories.conf"
        ;;

    *)
        echo "Error: unknown command: $COMMAND" >&2
        echo >&2
        usage
        exit 2
        ;;
esac

[[ -x "$SCRIPT" ]] || {
    echo "Error: command not found or not executable: $SCRIPT" >&2
    exit 1
}

[[ -f "$CONFIG" ]] || {
    echo "Error: configuration file not found: $CONFIG" >&2
    exit 1
}

# Set up the shared Python environment.
"$ROOT/setup/setup_python.sh" "$SETUP_CONFIG"

source "$ROOT/setup/python_venv/bin/activate"
ABCA_CONFIG_DIR="$CONFDIR" "$SCRIPT" "$CONFIG"

echo
echo "Command completed successfully."
echo "Command:               $COMMAND"
echo "Configuration profile: $CONFDIR"
echo "Working directory:     $ROOT"
