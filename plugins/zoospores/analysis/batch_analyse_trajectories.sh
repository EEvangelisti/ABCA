```bash
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
#       TRACKS_ROOT OUTPUT_ROOT TEMPLATE_CONFDIR [MAX_JOBS] [PYTHON_COMMAND]

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASH_SCRIPTS="$ROOT/bash-scripts"

# shellcheck disable=SC1091
source "$BASH_SCRIPTS/utils.sh"

usage() {
    cat >&2 <<'EOF'
Usage:
  ./batch_analyse_trajectories.sh \
      TRACKS_ROOT OUTPUT_ROOT TEMPLATE_CONFDIR [MAX_JOBS] [PYTHON_COMMAND]

Arguments:
  TRACKS_ROOT      Directory containing tracks_001, tracks_002, etc.
  OUTPUT_ROOT      Parent directory for trajectory_analysis_001, etc.
  TEMPLATE_CONFDIR Directory containing the standard analysis configuration files.
  MAX_JOBS         Maximum number of parallel analyses.
                   Defaults to one quarter of the available CPUs.
  PYTHON_COMMAND   Optional Python command forwarded to setup_python.sh.
EOF
    exit 2
}

(( $# >= 3 && $# <= 5 )) || usage

TRACKS_ROOT="$1"
OUTPUT_ROOT="$2"
TEMPLATE_CONFDIR="$3"
PYTHON_COMMAND="${5:-}"

require_directory "$TRACKS_ROOT" "Tracks root directory"
require_directory "$TEMPLATE_CONFDIR" "Template configuration directory"

TRACKS_ROOT="$(realpath -e -- "$TRACKS_ROOT")"
OUTPUT_ROOT="$(realpath -m -- "$OUTPUT_ROOT")"
TEMPLATE_CONFDIR="$(realpath -e -- "$TEMPLATE_CONFDIR")"

require_executable "$ROOT/analyse_trajectories.sh" \
    "Trajectory-analysis runner"

require_executable "$BASH_SCRIPTS/setup_python.sh" \
    "Python setup script"

require_file \
    "$TEMPLATE_CONFDIR/extract_trajectory_metrics.conf" \
    "Trajectory-extraction configuration"

require_file \
    "$TEMPLATE_CONFDIR/analyse_trajectory_metrics.conf" \
    "Trajectory-analysis configuration"

require_file \
    "$TEMPLATE_CONFDIR/plot_trajectory_overview.conf" \
    "Trajectory-overview configuration"

# Maximum number of parallel jobs; defaults to one quarter of available CPUs.
CPU_COUNT="$(nproc)"
MAX_JOBS="${4:-$(( CPU_COUNT / 4 ))}"

# Ensure at least one job on machines with fewer than four CPUs.
(( MAX_JOBS >= 1 )) || MAX_JOBS=1

require_integer MAX_JOBS "<=" "$CPU_COUNT"

mkdir -p "$OUTPUT_ROOT"

shopt -s nullglob
track_dirs=("$TRACKS_ROOT"/tracks_*)
shopt -u nullglob

valid_track_dirs=()

for directory in "${track_dirs[@]}"; do
    [[ -d "$directory" ]] && valid_track_dirs+=("$directory")
done

(( ${#valid_track_dirs[@]} > 0 )) \
    || die "No tracks_* directories found in $TRACKS_ROOT"

# Set up the shared Python environment once before launching parallel analyses.
if [[ -n "$PYTHON_COMMAND" ]]; then
    "$BASH_SCRIPTS/setup_python.sh" "$PYTHON_COMMAND"
else
    "$BASH_SCRIPTS/setup_python.sh"
fi

# Prevent child runners from reinstalling Python packages.
export SKIP_PYTHON_SETUP=1

# Replace one shell-style KEY=... assignment in a copied configuration file.
replace_config_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    local temporary="${file}.tmp"
    local status=0

    awk -v key="$key" -v value="$value" '
        BEGIN {
            replaced = 0
        }

        $0 ~ "^[[:space:]]*" key "=" {
            print key "=\"" value "\""
            replaced = 1
            next
        }

        {
            print
        }

        END {
            if (!replaced) {
                exit 42
            }
        }
    ' "$file" > "$temporary" || status=$?

    if (( status != 0 )); then
        rm -f -- "$temporary"

        if (( status == 42 )); then
            die "Variable '$key' not found in $file"
        fi

        die "Could not update variable '$key' in $file"
    fi

    mv -- "$temporary" "$file"
}

total="${#valid_track_dirs[@]}"
index=0

for tracks_dir in "${valid_track_dirs[@]}"; do
    wait_for_job_slot "$MAX_JOBS"

    ((index += 1))

    tracks_name="$(basename -- "$tracks_dir")"
    suffix="${tracks_name#tracks_}"

    if [[ "$suffix" == "$tracks_name" || -z "$suffix" ]]; then
        printf 'Warning: skipping unexpected directory name: %s\n' \
            "$tracks_name" >&2
        continue
    fi

    analysis_dir="$OUTPUT_ROOT/trajectory_analysis_$suffix"
    metrics_dir="$analysis_dir/metrics"
    grouped_analysis_dir="$analysis_dir/grouped_analysis"
    overview_dir="$analysis_dir/trajectory_overview"

    job_index="$index"

    (
        confdir="$(mktemp -d \
            "$OUTPUT_ROOT/.trajectory_analysis_${suffix}_conf.XXXXXX")"

        cleanup() {
            rm -rf -- "$confdir"
        }

        trap cleanup EXIT INT TERM

        extraction_conf="$confdir/extract_trajectory_metrics.conf"
        analysis_conf="$confdir/analyse_trajectory_metrics.conf"
        overview_conf="$confdir/plot_trajectory_overview.conf"

        printf '[%d/%d] Analysing %s...\n' \
            "$job_index" "$total" "$tracks_name"

        mkdir -p "$analysis_dir"

        cp -- \
            "$TEMPLATE_CONFDIR/extract_trajectory_metrics.conf" \
            "$extraction_conf"

        cp -- \
            "$TEMPLATE_CONFDIR/analyse_trajectory_metrics.conf" \
            "$analysis_conf"

        cp -- \
            "$TEMPLATE_CONFDIR/plot_trajectory_overview.conf" \
            "$overview_conf"

        replace_config_value \
            "$extraction_conf" \
            XML_SOURCE \
            "$tracks_dir"

        replace_config_value \
            "$extraction_conf" \
            OUTPUT_DIR \
            "$metrics_dir"

        replace_config_value \
            "$analysis_conf" \
            METRICS_DIR \
            "$metrics_dir"

        replace_config_value \
            "$analysis_conf" \
            GROUPED_ANALYSIS_DIR \
            "$grouped_analysis_dir"

        replace_config_value \
            "$overview_conf" \
            FILTERED_METRICS_DIR \
            ""

        replace_config_value \
            "$overview_conf" \
            COMPLETE_METRICS_DIR \
            "$metrics_dir"

        replace_config_value \
            "$overview_conf" \
            OVERVIEW_DIR \
            "$overview_dir"

        "$ROOT/analyse_trajectories.sh" "$confdir"

        printf '[%d/%d] Completed %s -> trajectory_analysis_%s\n' \
            "$job_index" "$total" "$tracks_name" "$suffix"
    ) &
done

wait

job_done "All trajectory analyses completed successfully"
```

