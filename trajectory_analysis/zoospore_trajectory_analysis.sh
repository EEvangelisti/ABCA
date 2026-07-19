#!/usr/bin/env bash
#
# Complete zoospore trajectory-analysis workflow
#
# Usage:
#   ./zoospore_trajectory_analysis.sh CONFIG_FILE
#
# The configuration file must contain KEY=value assignments. Values defined
# there override the defaults declared in this script. Relative paths are
# interpreted relative to the configuration file directory.
#

set -Eeuo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log() {
    (( QUIET )) || printf '%s\n' "$*"
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

section() {
    (( QUIET )) || {
        printf '\n%s\n%s\n%s\n' \
            '================================================================' \
            "$1" \
            '================================================================'
    }
}

usage() {
    cat <<EOF_USAGE
Usage:
  $(basename "$0") CONFIG_FILE

CONFIG_FILE must contain KEY=value assignments. Configuration values override
this script's defaults. Relative paths are resolved from the configuration
file directory.
EOF_USAGE
}

resolve_path() {
    local path="$1"

    if [[ "$path" = /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s/%s\n' "$CONFIG_DIR" "$path"
    fi
}

validate_config_file() {
    local line
    local line_number=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( ++line_number ))

        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ ! "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]]; then
            die "Invalid configuration entry at ${CONFIG_FILE}:${line_number}: $line"
        fi
    done < "$CONFIG_FILE"
}

# -----------------------------------------------------------------------------
# Script location and built-in defaults
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Input and output paths.
XML_SOURCE="tracks"
OUTPUT_ROOT="trajectory_analysis"

# Project layout.
PYTHON_DIR="$SCRIPT_DIR/python_scripts"
VENV_DIR="$SCRIPT_DIR/python_venvs/zoospore_env"
PYTHON_COMMAND="/usr/bin/env python3"

# Actions.
EXTRACT_METRICS=1
MAKE_METRICS_PLOTS=1
TRAJECTORY_OVERVIEW=1
EXTRACT_ABCA_PARAMETERS=1
RUN_HMM=1

# General trajectory parameters.
FRAME_INTERVAL_S=0.07
COORD_SCALE=1
SPATIAL_UNIT="micron"
MIN_SPOTS=10
DIRECTION_THRESHOLD_DEG=30
MAX_LAG=25
DPI=300

# Trajectory overview.
ANGULAR_BINS=36
MAX_TRACKS_PER_DECILE=0

# HMM analysis.
HMM_MIN_STATES=2
HMM_MAX_STATES=7
HMM_INITIALIZATIONS=10
HMM_COVARIANCE_TYPE="diag"
HMM_MIN_TRACK_OBSERVATIONS=10
HMM_TRANSITION_GRAPH_THRESHOLD=0.02
HMM_MAX_TRACKS_PLOT=200

# Terminal output.
QUIET=0

# -----------------------------------------------------------------------------
# Read configuration passed as $1
# -----------------------------------------------------------------------------

if (( $# != 1 )); then
    usage >&2
    exit 1
fi

case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
esac

CONFIG_FILE="$1"
[[ -f "$CONFIG_FILE" ]] || die "Configuration file not found: $CONFIG_FILE"

CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
CONFIG_DIR="$(dirname "$CONFIG_FILE")"

validate_config_file

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Resolve configurable paths after loading the configuration, so values in the
# configuration file override the defaults above.
XML_SOURCE="$(resolve_path "$XML_SOURCE")"
OUTPUT_ROOT="$(resolve_path "$OUTPUT_ROOT")"
PYTHON_DIR="$(resolve_path "$PYTHON_DIR")"
VENV_DIR="$(resolve_path "$VENV_DIR")"

[[ -e "$XML_SOURCE" ]] || die "XML source not found: $XML_SOURCE"
[[ -d "$PYTHON_DIR" ]] || die "Python script directory not found: $PYTHON_DIR"

# -----------------------------------------------------------------------------
# Output layout
# -----------------------------------------------------------------------------

METRICS_DIR="$OUTPUT_ROOT/metrics"
GROUPED_ANALYSIS_DIR="$OUTPUT_ROOT/grouped_analysis"
OVERVIEW_DIR="$OUTPUT_ROOT/trajectory_overview"
ABCA_DIR="$OUTPUT_ROOT/abca_parameters"
HMM_DIR="$OUTPUT_ROOT/hmm_analysis"

mkdir -p \
    "$METRICS_DIR" \
    "$GROUPED_ANALYSIS_DIR" \
    "$OVERVIEW_DIR" \
    "$ABCA_DIR" \
    "$HMM_DIR"

# -----------------------------------------------------------------------------
# Python environment and dependency verification
# -----------------------------------------------------------------------------

setup_python_environment() {
    local -a system_python
    local old_ifs="$IFS"

    IFS=' ' read -r -a system_python <<< "$PYTHON_COMMAND"
    IFS="$old_ifs"

    (( ${#system_python[@]} > 0 )) || die "PYTHON_COMMAND is empty"

    if [[ ! -x "$VENV_DIR/bin/python" ]]; then
        log "Creating Python virtual environment: $VENV_DIR"
        mkdir -p "$(dirname "$VENV_DIR")"

        "${system_python[@]}" -m venv "$VENV_DIR" \
            || die "Unable to create virtual environment"
    fi

    PYTHON="$VENV_DIR/bin/python"

    log "Upgrading pip..."
    "$PYTHON" -m pip install -q --upgrade pip

    log "Installing Python packages..."
    "$PYTHON" -m pip install -q --upgrade \
        numpy \
        pandas \
        scipy \
        matplotlib \
        scikit-learn \
        hmmlearn \
        tol-colors
}

require_python_script() {
    local script="$PYTHON_DIR/$1"
    [[ -f "$script" ]] || die "Python script not found: $script"
    printf '%s\n' "$script"
}

run_python() {
    local script_name="$1"
    shift
    "$PYTHON" "$(require_python_script "$script_name")" "$@"
}

# -----------------------------------------------------------------------------
# Analysis stages
# -----------------------------------------------------------------------------

extract_trajectory_metrics() {
    (( EXTRACT_METRICS )) || {
        log "Skipping trajectory metrics extraction."
        return 0
    }

    section "Extracting trajectory metrics"

    run_python characterize_zoospore_trajectories.py \
        "$XML_SOURCE" \
        --outdir "$METRICS_DIR" \
        --dt "$FRAME_INTERVAL_S" \
        --coord-scale "$COORD_SCALE" \
        --unit "$SPATIAL_UNIT" \
        --min-spots "$MIN_SPOTS" \
        --direction-threshold-deg "$DIRECTION_THRESHOLD_DEG" \
        --max-lag "$MAX_LAG"
}

analyse_trajectory_metrics() {
    (( MAKE_METRICS_PLOTS )) || {
        log "Skipping trajectory metrics plots."
        return 0
    }

    section "Analysing trajectory metrics"

    run_python analyze_zoospore_trajectory_metrics.py \
        "$METRICS_DIR" \
        --outdir "$GROUPED_ANALYSIS_DIR" \
        --dpi "$DPI"
}

generate_trajectory_overview() {
    (( TRAJECTORY_OVERVIEW )) || {
        log "Skipping trajectory overview."
        return 0
    }

    section "Generating trajectory overview"

    run_python plot_isotropy_and_centered_trajectories.py \
        "$METRICS_DIR" \
        --outdir "$OVERVIEW_DIR" \
        --angular-bins "$ANGULAR_BINS" \
        --max-tracks-per-decile "$MAX_TRACKS_PER_DECILE" \
        --dpi "$DPI"
}

prepare_abca_parameters() {
    (( EXTRACT_ABCA_PARAMETERS )) || {
        log "Skipping ABCA parameter extraction."
        return 0
    }

    section "Preparing ABCA parameters"

    run_python extract_abca_local_parameters.py \
        "$METRICS_DIR" \
        --outdir "$ABCA_DIR"
}

fit_hidden_markov_models() {
    (( RUN_HMM )) || {
        log "Skipping HMM analysis."
        return 0
    }

    section "Fitting and interpreting hidden Markov models"

    run_python fit_and_interpret_zoospore_hmm.py \
        "$METRICS_DIR" \
        --outdir "$HMM_DIR" \
        --dt "$FRAME_INTERVAL_S" \
        --min-states "$HMM_MIN_STATES" \
        --max-states "$HMM_MAX_STATES" \
        --initializations "$HMM_INITIALIZATIONS" \
        --covariance-type "$HMM_COVARIANCE_TYPE" \
        --min-track-observations "$HMM_MIN_TRACK_OBSERVATIONS" \
        --transition-graph-threshold "$HMM_TRANSITION_GRAPH_THRESHOLD" \
        --max-tracks-plot "$HMM_MAX_TRACKS_PLOT" \
        --dpi "$DPI"
}

# -----------------------------------------------------------------------------
# Main workflow
# -----------------------------------------------------------------------------

main() {
    section "Zoospore trajectory analysis"
    log "Configuration: $CONFIG_FILE"
    log "XML source:    $XML_SOURCE"
    log "Output root:   $OUTPUT_ROOT"

    setup_python_environment

    extract_trajectory_metrics
    analyse_trajectory_metrics
    generate_trajectory_overview
    prepare_abca_parameters
    fit_hidden_markov_models

    section "Workflow completed"
    log "Metrics:          $METRICS_DIR"
    log "Grouped analysis: $GROUPED_ANALYSIS_DIR"
    log "Overview:         $OVERVIEW_DIR"
    log "ABCA parameters:  $ABCA_DIR"
    (( RUN_HMM )) && log "HMM analysis:     $HMM_DIR"
}

main
