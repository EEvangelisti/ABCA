#!/usr/bin/env bash
set -Eeuo pipefail

# Analyse several independent trajectory datasets in parallel.
#
# Expected input layout:
#
#   TRACKS_ROOT/
#   ├── tracks_001/
#   ├── tracks_002/
#   └── ...
#
# Each input directory is analysed independently and written to:
#
#   OUTPUT_ROOT/
#   ├── trajectory_analysis_001/
#   ├── trajectory_analysis_002/
#   └── ...
#
# Usage:
#   ./batch_analyse_trajectories.sh TRACKS_ROOT OUTPUT_ROOT [MAX_JOBS] [SETUP_CONFIG]

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    cat >&2 <<'EOF'
Usage:
  ./batch_analyse_trajectories.sh TRACKS_ROOT OUTPUT_ROOT [MAX_JOBS] [SETUP_CONFIG]

Arguments:
  TRACKS_ROOT   Directory containing tracks_001, tracks_002, etc.
  OUTPUT_ROOT   Parent directory in which trajectory_analysis_001, etc. are created.
  MAX_JOBS      Maximum number of analyses run in parallel (default: 5).
  SETUP_CONFIG  Optional argument forwarded to setup/setup_python.sh.
EOF
}

if (( $# < 2 || $# > 4 )); then
    usage
    exit 2
fi

TRACKS_ROOT="$(realpath -e -- "$1")"
OUTPUT_ROOT="$(realpath -m -- "$2")"
MAX_JOBS="${3:-5}"
SETUP_CONFIG="${4:-}"

if [[ ! -d "$TRACKS_ROOT" ]]; then
    echo "Error: tracks root not found: $TRACKS_ROOT" >&2
    exit 1
fi

if ! [[ "$MAX_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: MAX_JOBS must be a positive integer." >&2
    exit 2
fi

for required_file in \
    "setup/setup_python.sh" \
    "trajectory_analysis/metrics_extraction/extract_trajectory_metrics.sh" \
    "trajectory_analysis/metrics_extraction/extract_trajectory_metrics.conf" \
    "trajectory_analysis/metrics_analysis/analyse_trajectory_metrics.sh" \
    "trajectory_analysis/metrics_analysis/analyse_trajectory_metrics.conf" \
    "trajectory_analysis/plotting_overviews/plot_trajectory_overview.sh" \
    "trajectory_analysis/plotting_overviews/plot_trajectory_overview.conf"
do
    if [[ ! -f "$required_file" ]]; then
        echo "Error: required file not found: $SCRIPT_DIR/$required_file" >&2
        exit 1
    fi
done

mkdir -p "$OUTPUT_ROOT"

shopt -s nullglob
track_dirs=("$TRACKS_ROOT"/tracks_*)
shopt -u nullglob

valid_track_dirs=()
for directory in "${track_dirs[@]}"; do
    [[ -d "$directory" ]] && valid_track_dirs+=("$directory")
done

if (( ${#valid_track_dirs[@]} == 0 )); then
    echo "Error: no tracks_* directories found in $TRACKS_ROOT" >&2
    exit 1
fi

# Set up the shared Python environment once before launching parallel analyses.
(
    cd setup
    ./setup_python.sh "$SETUP_CONFIG"
)

# Replace one shell-style KEY=... assignment in a copied configuration file.
replace_config_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    local temporary="${file}.tmp"

    awk -v key="$key" -v value="$value" '
        BEGIN { replaced = 0 }
        $0 ~ "^[[:space:]]*" key "=" {
            print key "=\"" value "\""
            replaced = 1
            next
        }
        { print }
        END {
            if (!replaced) {
                exit 42
            }
        }
    ' "$file" > "$temporary" || {
        status=$?
        rm -f -- "$temporary"
        if (( status == 42 )); then
            echo "Error: variable $key not found in $file" >&2
        fi
        return "$status"
    }

    mv -- "$temporary" "$file"
}

total="${#valid_track_dirs[@]}"
index=0

for tracks_dir in "${valid_track_dirs[@]}"; do
    ((index += 1))

    tracks_name="$(basename -- "$tracks_dir")"
    suffix="${tracks_name#tracks_}"

    if [[ "$suffix" == "$tracks_name" || -z "$suffix" ]]; then
        echo "Warning: skipping unexpected directory name: $tracks_name" >&2
        continue
    fi

    analysis_dir="$OUTPUT_ROOT/trajectory_analysis_$suffix"
    metrics_dir="$analysis_dir/metrics"
    grouped_analysis_dir="$analysis_dir/grouped_analysis"
    overview_dir="$analysis_dir/trajectory_overview"

    (
        extraction_module="$SCRIPT_DIR/trajectory_analysis/metrics_extraction"
        analysis_module="$SCRIPT_DIR/trajectory_analysis/metrics_analysis"
        overview_module="$SCRIPT_DIR/trajectory_analysis/plotting_overviews"

        extraction_conf="$extraction_module/extract_trajectory_metrics_${suffix}.conf"
        analysis_conf="$analysis_module/analyse_trajectory_metrics_${suffix}.conf"
        overview_conf="$overview_module/plot_trajectory_overview_${suffix}.conf"

        cleanup() {
            rm -f -- "$extraction_conf" "$analysis_conf" "$overview_conf"
        }
        trap cleanup EXIT INT TERM

        echo "[$index/$total] Analysing $tracks_name..."

        mkdir -p "$analysis_dir"

        # Create dataset-specific configuration files from the standard templates.
        cp -- "$extraction_module/extract_trajectory_metrics.conf" "$extraction_conf"
        cp -- "$analysis_module/analyse_trajectory_metrics.conf" "$analysis_conf"
        cp -- "$overview_module/plot_trajectory_overview.conf" "$overview_conf"

        replace_config_value "$extraction_conf" "XML_SOURCE" "$tracks_dir"
        replace_config_value "$extraction_conf" "OUTPUT_DIR" "$metrics_dir"

        replace_config_value "$analysis_conf" "METRICS_DIR" "$metrics_dir"
        replace_config_value "$analysis_conf" "GROUPED_ANALYSIS_DIR" "$grouped_analysis_dir"

        # Read the filtering settings from the specialised extraction
        # configuration so that the overview step consumes the correct output.
        # shellcheck disable=SC1090
        source "$extraction_conf"

        if [[ "${LENGTH_FILTER_MODE:-none}" == "none" ]]; then
            filtered_metrics_dir=""
        else
            if [[ -z "${FILTERED_SUBDIR:-}" ]]; then
                echo "Error: FILTERED_SUBDIR must be defined when LENGTH_FILTER_MODE is not 'none'." >&2
                exit 1
            fi
            filtered_metrics_dir="$metrics_dir/$FILTERED_SUBDIR"
        fi

        replace_config_value "$overview_conf" "FILTERED_METRICS_DIR" "$filtered_metrics_dir"
        replace_config_value "$overview_conf" "COMPLETE_METRICS_DIR" "$metrics_dir"
        replace_config_value "$overview_conf" "OVERVIEW_DIR" "$overview_dir"

        (
            cd "$extraction_module"
            ./extract_trajectory_metrics.sh "$(basename -- "$extraction_conf")"
        )

        (
            cd "$analysis_module"
            ./analyse_trajectory_metrics.sh "$(basename -- "$analysis_conf")"
        )

        (
            cd "$overview_module"
            ./plot_trajectory_overview.sh "$(basename -- "$overview_conf")"
        )

        echo "[$index/$total] Completed $tracks_name -> trajectory_analysis_$suffix"
    ) &

    while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
        wait -n
    done
done

wait

echo "All trajectory analyses completed successfully."
