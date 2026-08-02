#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$ROOT/utils.sh"

initialize_environment "$ROOT" "apply_burn_in.py" "$@"

# ------------------------------------------------------------------------------

require_variables PYTHON PYTHON_SCRIPT XML_SOURCE OUTPUT_DIR

if [[ -d "$XML_SOURCE" ]]; then
    require_directory "$XML_SOURCE" "XML source directory"
elif [[ -f "$XML_SOURCE" ]]; then
    require_file "$XML_SOURCE" "XML source file"
else
    die "XML source not found: $XML_SOURCE"
fi

# Number of initial frames removed.
BURN_IN_FRAMES="${BURN_IN_FRAMES:-0}"
require_integer BURN_IN_FRAMES non-negative

# Minimum number of spots required after burn-in.
MIN_REMAINING_SPOTS="${MIN_REMAINING_SPOTS:-10}"
require_integer MIN_REMAINING_SPOTS positive

# Burn-in reference: absolute acquisition frames or each trajectory start.
BURN_IN_MODE="${BURN_IN_MODE:-absolute}"
require_choice BURN_IN_MODE absolute relative

# Pattern used when XML_SOURCE is a directory.
XML_PATTERN="${XML_PATTERN:-*.xml}"

# Name of the CSV summary written to OUTPUT_DIR.
SUMMARY_FILENAME="${SUMMARY_FILENAME:-burn_in_summary.csv}"

# Whether to pretty-print output XML files.
INDENT_XML="${INDENT_XML:-false}"
require_choice INDENT_XML 0 1 true false yes no on off

args=(
    "$XML_SOURCE"
    --outdir "$OUTPUT_DIR"
    --burn-in-frames "$BURN_IN_FRAMES"
    --min-remaining-spots "$MIN_REMAINING_SPOTS"
    --mode "$BURN_IN_MODE"
    --pattern "$XML_PATTERN"
    --summary-filename "$SUMMARY_FILENAME"
)

case "$INDENT_XML" in
    1|true|yes|on)
        args+=(--indent-xml)
        ;;
esac

mkdir -p "$OUTPUT_DIR"

cat <<EOF
Applying trajectory burn-in
===========================
XML source:              $XML_SOURCE
Output directory:        $OUTPUT_DIR
Burn-in frames:          $BURN_IN_FRAMES
Burn-in mode:            $BURN_IN_MODE
Minimum remaining spots: $MIN_REMAINING_SPOTS
XML pattern:             $XML_PATTERN
Summary file:            $SUMMARY_FILENAME

EOF

"$PYTHON" "$PYTHON_SCRIPT" "${args[@]}"

job_done "Trajectory burn-in completed"
