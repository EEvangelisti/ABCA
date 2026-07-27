#!/usr/bin/env bash
#
# Complete zoospore trajectory-analysis workflow.
#
# This launcher requires Bash; it is not intended to run under a strictly
# POSIX-compliant /bin/sh. Bash arrays are used to preserve argument boundaries
# when optional command-line arguments are assembled.
#
# Usage:
#   ./zoospore_trajectory_analysis.sh CONFIG_FILE
#
# The configuration file is sourced as a trusted Bash fragment and should
# contain only KEY=value assignments. Values defined there override the defaults
# declared in this script. Relative paths are interpreted relative to the
# configuration file directory. Do not use an untrusted configuration file.
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

CONFIG_FILE is sourced as a trusted Bash fragment and should contain KEY=value
assignments. Configuration values override this script's defaults. Relative
paths are resolved from the configuration file directory.
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

# Perform a lightweight syntax check before sourcing the configuration. This
# catches accidental prose or malformed assignments, but it is not a security
# sandbox: the configuration file must still be trusted.
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

# Input and output paths. Relative paths are resolved from the directory that
# contains the selected configuration file.
XML_SOURCE="tracks"
OUTPUT_ROOT="trajectory_analysis"
ANALYSIS_METRICS_SUBDIR=""

# Project layout.
PYTHON_DIR="$SCRIPT_DIR/python_scripts"
VENV_DIR="$SCRIPT_DIR/zsp_venv"
PYTHON_COMMAND="/usr/bin/env python3"

# Actions.
EXTRACT_METRICS=1
MAKE_METRICS_PLOTS=1
TEST_FAST_SLOW_HYSTERESIS=1
TRAJECTORY_OVERVIEW=1
EXTRACT_ABCA_PARAMETERS=1
RUN_HMM=1

# Metric extraction and filtering.
LENGTH_FILTER_MODE="percentile"  # percentile, max_points, or none
LENGTH_FILTER_PERCENTILE=90
LENGTH_FILTER_MAX_POINTS=0
FILTERED_METRICS_SUBDIR="filtered_90th_percentile"

# General trajectory parameters.
FRAME_INTERVAL_S=0.07
COORD_SCALE=1
SPATIAL_UNIT="micron"
MIN_SPOTS=10
DIRECTION_THRESHOLD_DEG=30
MAX_LAG=25
DPI=300

# SLOW/FAST classification and hysteresis sensitivity analysis.
# Widths are comma-separated and interpreted by the corresponding Python script.
HYSTERESIS_WIDTHS="0,5,10,15,20,30,40"
HYSTERESIS_OTSU_BINS=256
HYSTERESIS_HISTOGRAM_BINS=50
HYSTERESIS_HALF_WIDTH=25

# Trajectory overview.
ANGULAR_BINS=36
MAX_TRACKS=0
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
ANALYSIS_METRICS_DIR="$METRICS_DIR"
if [[ -n "$ANALYSIS_METRICS_SUBDIR" ]]; then
    ANALYSIS_METRICS_DIR="$METRICS_DIR/$ANALYSIS_METRICS_SUBDIR"
fi
GROUPED_ANALYSIS_DIR="$OUTPUT_ROOT/grouped_analysis"
HYSTERESIS_DIR="$OUTPUT_ROOT/fast_slow_hysteresis_sensitivity"
OVERVIEW_DIR="$OUTPUT_ROOT/trajectory_overview"
ABCA_DIR="$OUTPUT_ROOT/abca_parameters"
HMM_DIR="$OUTPUT_ROOT/hmm_analysis"

mkdir -p \
    "$METRICS_DIR" \
    "$ANALYSIS_METRICS_DIR" \
    "$GROUPED_ANALYSIS_DIR" \
    "$HYSTERESIS_DIR" \
    "$OVERVIEW_DIR" \
    "$ABCA_DIR" \
    "$HMM_DIR"

# -----------------------------------------------------------------------------
# Python environment and dependency verification
# -----------------------------------------------------------------------------

# Create the virtual environment when absent, then ensure that all runtime
# dependencies are installed. PYTHON_COMMAND may contain a command plus simple
# arguments (for example, "python3.12" or "/usr/bin/env python3").
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

    # A Bash array is used here so each optional argument remains a distinct
    # shell word, including when a configured value contains spaces.
    local filter_args=()

    case "$LENGTH_FILTER_MODE" in
        percentile)
            filter_args+=(
                --length-filter-percentile "$LENGTH_FILTER_PERCENTILE"
                --filtered-subdir "$FILTERED_METRICS_SUBDIR"
            )
            ;;

        max_points)
            filter_args+=(
                --length-filter-max-points "$LENGTH_FILTER_MAX_POINTS"
                --filtered-subdir "$FILTERED_METRICS_SUBDIR"
            )
            ;;

        none)
            filter_args+=(--no-length-filter)
            ;;

        *)
            die "Invalid LENGTH_FILTER_MODE: $LENGTH_FILTER_MODE"
            ;;
    esac

    section "Extracting trajectory metrics"

    run_python extract_trajectory_metrics.py \
        "$XML_SOURCE" \
        --outdir "$METRICS_DIR" \
        --dt "$FRAME_INTERVAL_S" \
        --coord-scale "$COORD_SCALE" \
        --unit "$SPATIAL_UNIT" \
        --min-spots "$MIN_SPOTS" \
        --direction-threshold-deg "$DIRECTION_THRESHOLD_DEG" \
        --max-lag "$MAX_LAG" \
        "${filter_args[@]}"
}

analyse_trajectory_metrics() {
    (( MAKE_METRICS_PLOTS )) || {
        log "Skipping trajectory metrics plots."
        return 0
    }

    section "Analysing trajectory metrics"

    run_python analyze_zoospore_trajectory_metrics.py \
        "$ANALYSIS_METRICS_DIR" \
        --outdir "$GROUPED_ANALYSIS_DIR" \
        --dpi "$DPI"
}

analyse_fast_slow_hysteresis() {
    (( TEST_FAST_SLOW_HYSTERESIS )) || {
        log "Skipping FAST/SLOW hysteresis sensitivity analysis."
        return 0
    }

    section "Testing FAST/SLOW hysteresis widths"

    run_python analyse_fast_slow_hysteresis.py \
        "$ANALYSIS_METRICS_DIR" \
        --outdir "$HYSTERESIS_DIR" \
        --hysteresis-widths "$HYSTERESIS_WIDTHS" \
        --otsu-bins "$HYSTERESIS_OTSU_BINS" \
        --bins "$HYSTERESIS_HISTOGRAM_BINS" \
        --dpi "$DPI"
}

generate_trajectory_overview() {
    (( TRAJECTORY_OVERVIEW )) || {
        log "Skipping trajectory overview."
        return 0
    }

    section "Generating trajectory overview"

    run_python plot_trajectory_overview.py \
        "$ANALYSIS_METRICS_DIR" \
        --complete-metrics-dir "$METRICS_DIR" \
        --outdir "$OVERVIEW_DIR" \
        --angular-bins "$ANGULAR_BINS" \
        --max-tracks "$MAX_TRACKS" \
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
        "$ANALYSIS_METRICS_DIR" \
        --hysteresis-half-width "$HYSTERESIS_HALF_WIDTH" \
        --outdir "$ABCA_DIR"
}

fit_hidden_markov_models() {
    (( RUN_HMM )) || {
        log "Skipping HMM analysis."
        return 0
    }

    section "Fitting and interpreting hidden Markov models"

    run_python fit_and_interpret_zoospore_hmm_connectivity.py \
        "$ANALYSIS_METRICS_DIR" \
        --outdir "$HMM_DIR" \
        --dt "$FRAME_INTERVAL_S" \
        --min-states "$HMM_MIN_STATES" \
        --max-states "$HMM_MAX_STATES" \
        --initializations "$HMM_INITIALIZATIONS" \
        --covariance-type "$HMM_COVARIANCE_TYPE" \
        --min-track-observations "$HMM_MIN_TRACK_OBSERVATIONS" \
        --transition-graph-threshold "$HMM_TRANSITION_GRAPH_THRESHOLD" \
        --max-tracks-plot "$HMM_MAX_TRACKS_PLOT" \
        --dpi "$DPI" \
        --write-decoded-all
}

# -----------------------------------------------------------------------------
# Main workflow
# -----------------------------------------------------------------------------

# Execute stages sequentially. Each stage honours its corresponding action
# switch and returns successfully when disabled.
main() {
    section "Zoospore trajectory analysis"
    log "Configuration: $CONFIG_FILE"
    log "XML source:    $XML_SOURCE"
    log "Output root:   $OUTPUT_ROOT"

    setup_python_environment

    extract_trajectory_metrics
    analyse_trajectory_metrics
    analyse_fast_slow_hysteresis
    generate_trajectory_overview
    prepare_abca_parameters
    fit_hidden_markov_models

    section "Workflow completed"
    log "Metrics:          $ANALYSIS_METRICS_DIR"
    log "Grouped analysis: $GROUPED_ANALYSIS_DIR"
    (( TEST_FAST_SLOW_HYSTERESIS )) && log "Hysteresis:       $HYSTERESIS_DIR"
    log "Overview:         $OVERVIEW_DIR"
    log "ABCA parameters:  $ABCA_DIR"
    (( RUN_HMM )) && log "HMM analysis:     $HMM_DIR"
}

main
