# Shared functions

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage:
  $(basename "$0") CONFIG_FILE

CONFIG_FILE is a trusted Bash configuration file containing the
input/output paths and analysis parameters.
EOF
}

check_file() {
    local file="$1"
    local description="$2"
    [[ -f "$file" ]] || die "$description not found: $file"
}

initialize_environment() {
    local root="$1"
    local python_script="$2"
    shift 2

    case "${1:-}" in
        -h|--help)
            usage
            exit 0
            ;;
    esac

    (( $# == 1 )) || {
        usage >&2
        exit 1
    }

    ANALYSIS_CONFIG="$(realpath -- "$1")"
    PYTHON_SCRIPT="$root/../python-scripts/$python_script"

    check_file "$ANALYSIS_CONFIG" "Analysis configuration"
    check_file "$PYTHON_SCRIPT" "Python script"

    PYTHON="$root/../python-scripts/zsp_venv/bin/python"
    : "${PYTHON:?PYTHON is not defined in $PYTHON_CONFIG}"
    [[ -x "$PYTHON" ]] \
        || die "Python interpreter is not executable: $PYTHON"

    cd "$(dirname $ANALYSIS_CONFIG)"
    # shellcheck disable=SC1090
    source "$ANALYSIS_CONFIG"
}

require_variables() {
    local variable

    for variable in "$@"; do
        [[ -n "${!variable:-}" ]] \
            || die "Required variable '$variable' is not defined in $ANALYSIS_CONFIG."
    done
}

require_directory() {
    local directory="$1"
    local description="$2"

    [[ -d "$directory" ]] \
        || die "$description not found: $directory"
}

require_file() {
    local file="$1"
    local description="$2"

    [[ -f "$file" ]] \
        || die "$description not found: $file"
}

check_metrics_directory() {
    local directory="$1"
    require_directory "$directory" "Metrics directory"
    require_file "$directory/step_metrics.csv" "Step metrics file"
    require_file "$directory/track_metrics.csv" "Track metrics file"
}

require_number() {
    local name="$1"
    local value="${!name:-}"
    local status=0
    local op
    local ref

    shift

    # Accept signed integers and decimal numbers.
    [[ "$value" =~ ^-?([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] \
        || die "$name must be numeric (received: $value)"

    case "$#" in
        0)
            return
            ;;

        1)
            case "${1,,}" in
                non-negative)
                    set -- ">=" 0
                    ;;
                positive)
                    set -- ">" 0
                    ;;
                *)
                    die "Unknown numeric constraint: $1"
                    ;;
            esac
            ;;

        2|4)
            ;;

        *)
            die "Invalid numeric constraints for $name"
            ;;
    esac

    while (( $# > 0 )); do
        op="$1"
        ref="$2"
        shift 2

        [[ "$ref" =~ ^-?([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] \
            || die "Comparison value must be numeric (received: $ref)"

        status=0

        awk -v value="$value" -v ref="$ref" -v op="$op" '
            BEGIN {
                if      (op == ">")  valid = value >  ref
                else if (op == ">=") valid = value >= ref
                else if (op == "<")  valid = value <  ref
                else if (op == "<=") valid = value <= ref
                else if (op == "=" || op == "==") valid = value == ref
                else if (op == "!=") valid = value != ref
                else exit 2

                exit(valid ? 0 : 1)
            }
        ' || status=$?

        case "$status" in
            0)
                ;;
            1)
                die "$name must be $op $ref (received: $value)"
                ;;
            2)
                die "Unknown comparison operator: $op"
                ;;
            *)
                die "Numeric comparison failed for $name"
                ;;
        esac
    done
}

require_integer() {
    local name="$1"
    local value="${!name:-}"

    require_number "$@"

    [[ "$value" =~ ^-?[0-9]+$ ]] \
        || die "$name must be an integer (received: $value)"
}

require_choice() {
    local name="$1"
    local value="${!name:-}"
    local choice
    local normalized_value="${value,,}"

    shift

    (( $# > 0 )) \
        || die "No allowed values specified for $name"

    for choice in "$@"; do
        if [[ "$normalized_value" == "${choice,,}" ]]; then
            return 0
        fi
    done

    die "$name must be one of: $* (received: $value)"
}

job_done() {
  echo "$1."
  echo "---------------------------------------------------------"
}
