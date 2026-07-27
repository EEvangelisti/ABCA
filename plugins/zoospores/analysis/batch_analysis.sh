#!/usr/bin/env bash
#
# Run multiple zoospore trajectory analyses in parallel.
#
# For each index in the requested range, this script creates an analysis
# configuration file from trajectory_analysis.conf.template by replacing every
# occurrence of "XXX" with a zero-padded index. It then launches the main
# trajectory-analysis workflow, while limiting the number of concurrent jobs.
#
# Requirements:
#   - Bash 4.3 or later (for wait -n)
#   - A configuration template named trajectory_analysis.conf.template
#   - zoospore_trajectory_analysis.sh in the same directory as this script
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------

ROOT="$SCRIPT_DIR"
FIRST_INDEX=1
LAST_INDEX=100
MAX_JOBS=10
INDEX_WIDTH=3
ANALYSIS_SCRIPT="$SCRIPT_DIR/zoospore_trajectory_analysis.sh"
FAILED=0

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF_USAGE
Usage:
  $(basename "$0") [OPTIONS]

Options:
  -r, --root DIR          Batch root directory containing
                          trajectory_analysis.conf.template.
                          Default: $ROOT
  -f, --first-index N     First analysis index, inclusive.
                          Default: $FIRST_INDEX
  -l, --last-index N      Last analysis index, inclusive.
                          Default: $LAST_INDEX
  -j, --max-jobs N        Maximum number of concurrent analyses.
                          Default: $MAX_JOBS
  -h, --help              Show this help message and exit.
EOF_USAGE
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_option_argument() {
    local option="$1"
    local value="${2-}"

    [[ -n "$value" ]] || die "Option $option requires an argument"
}

is_non_negative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

running_jobs() {
    jobs -rp | wc -l
}

# Stop active child processes when the launcher is interrupted, preventing
# orphaned analyses from continuing after the parent process exits.
terminate_children() {
    local child_pids

    child_pids="$(jobs -rp)"
    if [[ -n "$child_pids" ]]; then
        printf '\nBatch interrupted; terminating active analyses...\n' >&2
        # Word splitting is intentional: child_pids contains one PID per line.
        # shellcheck disable=SC2086
        kill $child_pids 2>/dev/null || true
        wait 2>/dev/null || true
    fi
}

trap terminate_children INT TERM

# -----------------------------------------------------------------------------
# Command-line parsing
# -----------------------------------------------------------------------------

while (( $# > 0 )); do
    case "$1" in
        -r|--root)
            require_option_argument "$1" "${2-}"
            ROOT="$2"
            shift 2
            ;;
        -f|--first-index)
            require_option_argument "$1" "${2-}"
            FIRST_INDEX="$2"
            shift 2
            ;;
        -l|--last-index)
            require_option_argument "$1" "${2-}"
            LAST_INDEX="$2"
            shift 2
            ;;
        -j|--max-jobs)
            require_option_argument "$1" "${2-}"
            MAX_JOBS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            (( $# == 0 )) || die "Unexpected positional argument: $1"
            break
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            die "Unexpected positional argument: $1"
            ;;
    esac
done

# Resolve a user-supplied relative root from the current working directory.
ROOT="$(cd "$(dirname "$ROOT")" 2>/dev/null && pwd)/$(basename "$ROOT")"
TEMPLATE="$ROOT/trajectory_analysis.conf.template"

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

[[ -d "$ROOT" ]] || die "Batch root directory not found: $ROOT"
[[ -f "$TEMPLATE" ]] || die "Configuration template not found: $TEMPLATE"
[[ -f "$ANALYSIS_SCRIPT" ]] || die "Analysis script not found: $ANALYSIS_SCRIPT"
[[ -x "$ANALYSIS_SCRIPT" ]] || die "Analysis script is not executable: $ANALYSIS_SCRIPT"

is_non_negative_integer "$FIRST_INDEX" \
    || die "FIRST_INDEX must be a non-negative integer"
is_non_negative_integer "$LAST_INDEX" \
    || die "LAST_INDEX must be a non-negative integer"
is_positive_integer "$MAX_JOBS" \
    || die "MAX_JOBS must be a positive integer"

(( LAST_INDEX >= FIRST_INDEX )) \
    || die "LAST_INDEX must be greater than or equal to FIRST_INDEX"

grep -q 'XXX' "$TEMPLATE" \
    || die 'The configuration template does not contain the placeholder XXX'

# -----------------------------------------------------------------------------
# Batch execution
# -----------------------------------------------------------------------------

printf 'Batch root:  %s\n' "$ROOT"
printf 'Index range: %d-%d\n' "$FIRST_INDEX" "$LAST_INDEX"
printf 'Max jobs:    %d\n' "$MAX_JOBS"

for (( i = FIRST_INDEX; i <= LAST_INDEX; i++ )); do
    printf -v index "%0${INDEX_WIDTH}d" "$i"
    config_file="$ROOT/trajectory_analysis_${index}.conf"

    # The replacement value is numeric, so it cannot alter the sed expression.
    sed "s/XXX/${index}/g" "$TEMPLATE" > "$config_file"

    (
        printf '[%s] Starting\n' "$index"
        "$ANALYSIS_SCRIPT" "$config_file"
        printf '[%s] Completed\n' "$index"
    ) &

    # Reap one process whenever the concurrency limit is reached. A failed job
    # is recorded but does not prevent the remaining independent jobs from running.
    while (( $(running_jobs) >= MAX_JOBS )); do
        wait -n || FAILED=1
    done
done

# Reap all remaining analyses while preserving information about failures.
while jobs -rp | grep -q .; do
    wait -n || FAILED=1
done

trap - INT TERM

if (( FAILED )); then
    printf 'One or more analyses failed.\n' >&2
    exit 1
fi

printf 'All analyses completed successfully.\n'
