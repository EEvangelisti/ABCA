#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "fit_and_interpret_zoospore_hmm.py" "$@"

# ------------------------------------------------------------------------------

require_variables PYTHON PYTHON_SCRIPT METRICS_DIR
require_directory "$METRICS_DIR" "Metrics directory"
require_file "$METRICS_DIR/step_metrics.csv" "Step metrics file"
require_file "$METRICS_DIR/turn_metrics.csv" "Turn metrics file"

# Directory used to store HMM analysis outputs.
HMM_ANALYSIS_DIR="${HMM_ANALYSIS_DIR:-$METRICS_DIR/hmm_analysis}"

# Time interval between two consecutive observations (s).
DT="${DT:-0.22}"
require_number DT positive

# Minimum number of hidden states evaluated.
MIN_STATES="${MIN_STATES:-2}"
require_integer MIN_STATES ">=" 2

# Maximum number of hidden states evaluated.
MAX_STATES="${MAX_STATES:-7}"
require_integer MAX_STATES ">=" 2

(( MIN_STATES <= MAX_STATES )) \
    || die "MIN_STATES must be less than or equal to MAX_STATES."

# Number of random initializations per HMM.
INITIALIZATIONS="${INITIALIZATIONS:-10}"
require_integer INITIALIZATIONS ">=" 1

# Maximum number of EM iterations.
N_ITER="${N_ITER:-500}"
require_integer N_ITER positive

# Convergence tolerance for the EM algorithm.
TOL="${TOL:-0.0001}"
require_number TOL positive

# Covariance matrix type used by the HMM.
COVARIANCE_TYPE="${COVARIANCE_TYPE:-diag}"
require_choice COVARIANCE_TYPE spherical diag full tied

# Minimum number of observations required per trajectory.
MIN_TRACK_OBSERVATIONS="${MIN_TRACK_OBSERVATIONS:-10}"
require_integer MIN_TRACK_OBSERVATIONS positive

# Scaling factor applied to acceleration values.
ACCELERATION_SCALE="${ACCELERATION_SCALE:-100}"
require_number ACCELERATION_SCALE positive

# Minimum transition probability displayed in the transition graph.
TRANSITION_GRAPH_THRESHOLD="${TRANSITION_GRAPH_THRESHOLD:-0.02}"
require_number TRANSITION_GRAPH_THRESHOLD ">=" 0 "<=" 1

# Minimum transition probability considered for connectivity analysis.
CONNECTIVITY_THRESHOLD="${CONNECTIVITY_THRESHOLD:-0.02}"
require_number CONNECTIVITY_THRESHOLD ">=" 0 "<=" 1

# Minimum state occupancy retained for analysis.
MINIMUM_STATE_OCCUPANCY="${MINIMUM_STATE_OCCUPANCY:-0.01}"
require_number MINIMUM_STATE_OCCUPANCY ">" 0 "<=" 1

# Minimum posterior probability required for state assignment.
MINIMUM_STATE_POSTERIOR="${MINIMUM_STATE_POSTERIOR:-0.50}"
require_number MINIMUM_STATE_POSTERIOR ">" 0 "<=" 1

# Maximum number of trajectories displayed in diagnostic plots.
MAX_TRACKS_PLOT="${MAX_TRACKS_PLOT:-200}"
require_integer MAX_TRACKS_PLOT positive

# Number of points used to sample empirical quantile functions.
QUANTILE_COUNT="${QUANTILE_COUNT:-1001}"
require_integer QUANTILE_COUNT ">=" 2

# Resolution of the exported figures in dots per inch.
DPI="${DPI:-300}"
require_integer DPI positive

# Write decoded state sequences for all tested HMMs.
WRITE_DECODED_ALL="${WRITE_DECODED_ALL:-0}"
require_choice WRITE_DECODED_ALL "0" "1" "true" "false" "yes" "no" "on" "off"

args=(
    "$METRICS_DIR"
    --outdir "$HMM_ANALYSIS_DIR"
    --dt "$DT"
    --min-states "$MIN_STATES"
    --max-states "$MAX_STATES"
    --initializations "$INITIALIZATIONS"
    --n-iter "$N_ITER"
    --tol "$TOL"
    --covariance-type "$COVARIANCE_TYPE"
    --min-track-observations "$MIN_TRACK_OBSERVATIONS"
    --acceleration-scale "$ACCELERATION_SCALE"
    --transition-graph-threshold "$TRANSITION_GRAPH_THRESHOLD"
    --connectivity-threshold "$CONNECTIVITY_THRESHOLD"
    --minimum-state-occupancy "$MINIMUM_STATE_OCCUPANCY"
    --minimum-state-posterior "$MINIMUM_STATE_POSTERIOR"
    --max-tracks-plot "$MAX_TRACKS_PLOT"
    --quantile-count "$QUANTILE_COUNT"
    --dpi "$DPI"
)

case "${WRITE_DECODED_ALL,,}" in
    1|true|yes|on)
        args+=(--write-decoded-all)
        ;;
esac

mkdir -p "$HMM_ANALYSIS_DIR"

cat <<EOF
Fitting and interpreting zoospore HMMs
======================================
Metrics:                    $METRICS_DIR
Output:                     $HMM_ANALYSIS_DIR
Time step:                  $DT s
State range:                $MIN_STATES-$MAX_STATES
Initializations per model:  $INITIALIZATIONS
Maximum EM iterations:      $N_ITER
Convergence tolerance:      $TOL
Covariance type:            $COVARIANCE_TYPE
Minimum track observations: $MIN_TRACK_OBSERVATIONS
Acceleration scale:         $ACCELERATION_SCALE
Connectivity threshold:     $CONNECTIVITY_THRESHOLD
Minimum state occupancy:    $MINIMUM_STATE_OCCUPANCY
Minimum state posterior:    $MINIMUM_STATE_POSTERIOR
Quantiles per state:        $QUANTILE_COUNT
Write all decoded tables:   $WRITE_DECODED_ALL

EOF

"$PYTHON" "$PYTHON_SCRIPT" "${args[@]}"

job_done "HMM fitting and interpretation completed"
