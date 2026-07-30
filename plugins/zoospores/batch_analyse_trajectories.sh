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
#   ./batch_analyse_trajectories.sh \
#       TRACKS_ROOT OUTPUT_ROOT CONFDIR [MAX_JOBS] [SETUP_CONFIG]

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat >&2 <<'EOF'
Usage:
  ./batch_analyse_trajectories.sh \
      TRACKS_ROOT OUTPUT_ROOT CONFDIR [MAX_JOBS] [SETUP_CONFIG]

Arguments:
  TRACKS_ROOT   Directory containing tracks_001, tracks_002, etc.
  OUTPUT_ROOT   Parent directory in which trajectory_analysis_001, etc. are created.
  CONFDIR       Directory containing the configuration profile.
  MAX_JOBS      Maximum number of analyses run in parallel (default: 5).
  SETUP_CONFIG  Optional argument forwarded to setup/setup_python.sh.
EOF
}

if (( $# < 3 || $# > 5 )); then
    usage
    exit 2
fi

TRACKS_ROOT="$(realpath -e -- "$1")"
OUTPUT_ROOT="$(realpath -m -- "$2")"
CONFDIR="$(realpath -e -- "$3")"
MAX_JOBS="${4:-5}"
SETUP_CONFIG="${5:-}"

if [[ ! -d "$TRACKS_ROOT" ]]; then
    echo "Error: tracks root not found: $TRACKS_ROOT" >&2
    exit 1
fi

if [[ ! -d "$CONFDIR" ]]; then
    echo "Error: configuration directory not found: $CONFDIR" >&2
    exit 1
fi

if ! [[ "$MAX_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: MAX_JOBS must be a positive integer." >&2
    exit 2
fi

for required_file in \
    "$ROOT/setup/setup_python.sh" \
    "$ROOT/trajectory_analysis/metrics_extraction/extract_trajectory_metrics.sh" \
    "$ROOT/trajectory_analysis/metrics_analysis/analyse_trajectory_metrics.sh" \
    "$ROOT/trajectory_analysis/plotting_overviews/plot_trajectory_overview.sh" \
    "$CONFDIR/extract_trajectory_metrics.conf" \
    "$CONFDIR/analyse_trajectory_metrics.conf" \
    "$CONFDIR/plot_trajectory_overview.conf"
do
    if [[ ! -f "$required_file" ]]; then
        echo "Error: required file not found: $required_file" >&2
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
    cd "$ROOT/setup"
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
        local status=$?

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
        extraction_module="$ROOT/trajectory_analysis/metrics_extraction"
        analysis_module="$ROOT/trajectory_analysis/metrics_analysis"
        overview_module="$ROOT/trajectory_analysis/plotting_overviews"

        # Store the specialised configurations with their corresponding output.
        config_dir="$analysis_dir/configuration"

        extraction_conf="$config_dir/extract_trajectory_metrics.conf"
        analysis_conf="$config_dir/analyse_trajectory_metrics.conf"
        overview_conf="$config_dir/plot_trajectory_overview.conf"

        echo "[$index/$total] Analysing $tracks_name..."

        mkdir -p "$config_dir"

        # Create dataset-specific configuration files from the selected profile.
        cp -- \
            "$CONFDIR/extract_trajectory_metrics.conf" \
            "$extraction_conf"

        cp -- \
            "$CONFDIR/analyse_trajectory_metrics.conf" \
            "$analysis_conf"

        cp -- \
            "$CONFDIR/plot_trajectory_overview.conf" \
            "$overview_conf"

        replace_config_value \
            "$extraction_conf" \
            "XML_SOURCE" \
            "$tracks_dir"

        replace_config_value \
            "$extraction_conf" \
            "OUTPUT_DIR" \
            "$metrics_dir"

        replace_config_value \
            "$analysis_conf" \
            "METRICS_DIR" \
            "$metrics_dir"

        replace_config_value \
            "$analysis_conf" \
            "GROUPED_ANALYSIS_DIR" \
            "$grouped_analysis_dir"

        # Read the filtering settings from the specialised extraction
        # configuration so that the overview step consumes the correct output.
        # shellcheck disable=SC1090
        source "$extraction_conf"

        if [[ "${LENGTH_FILTER_MODE:-none}" == "none" ]]; then
            filtered_metrics_dir=""
        else
            if [[ -z "${FILTERED_SUBDIR:-}" ]]; then
                echo \
                    "Error: FILTERED_SUBDIR must be defined when" \
                    "LENGTH_FILTER_MODE is not 'none'." >&2
                exit 1
            fi

            filtered_metrics_dir="$metrics_dir/$FILTERED_SUBDIR"
        fi

        replace_config_value \
            "$overview_conf" \
            "FILTERED_METRICS_DIR" \
            "$filtered_metrics_dir"

        replace_config_value \
            "$overview_conf" \
            "COMPLETE_METRICS_DIR" \
            "$metrics_dir"

        replace_config_value \
            "$overview_conf" \
            "OVERVIEW_DIR" \
            "$overview_dir"

        (
            cd "$extraction_module"
            ./extract_trajectory_metrics.sh "$extraction_conf"
        )

        (
            cd "$analysis_module"
            ./analyse_trajectory_metrics.sh "$analysis_conf"
        )

        (
            cd "$overview_module"
            ./plot_trajectory_overview.sh "$overview_conf"
        )

        echo \
            "[$index/$total] Completed $tracks_name" \
            "-> trajectory_analysis_$suffix"
    ) &

    while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
        wait -n
    done
done

wait

echo
echo "All trajectory analyses completed successfully."
echo "Configuration profile: $CONFDIR"
