#!/usr/bin/env bash
# Shared optional presentation helpers for Shell_Tools.
# Sourcing this file has no side effects.

# shellcheck disable=SC2120
st_ui_init() {
    local requested="${1:-${COLOR_MODE:-auto}}"
    case "$requested" in
        auto|always|never) ;;
        --no-color) requested=never ;;
        *) requested=auto ;;
    esac
    case "$requested" in
        always) ST_UI_COLOR=1 ;;
        never) ST_UI_COLOR=0 ;;
        auto)
            if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then ST_UI_COLOR=1; else ST_UI_COLOR=0; fi
            ;;
    esac
    if [[ "${ST_UI_COLOR:-0}" == 1 ]]; then
        ST_UI_CYAN=$'\033[36m'; ST_UI_MAGENTA=$'\033[35m'; ST_UI_GREEN=$'\033[32m'
        ST_UI_YELLOW=$'\033[33m'; ST_UI_RED=$'\033[31m'; ST_UI_BOLD=$'\033[1m'; ST_UI_RESET=$'\033[0m'
    else
        ST_UI_CYAN=''; ST_UI_MAGENTA=''; ST_UI_GREEN=''; ST_UI_YELLOW=''; ST_UI_RED=''; ST_UI_BOLD=''; ST_UI_RESET=''
    fi
}

st_ui_emit() { local color="${1:-}" level="$2"; shift 2; printf '%b[%s] %s%b\n' "$color" "$level" "$*" "${ST_UI_RESET:-}" >&2; }
st_banner() { st_ui_emit "$ST_UI_CYAN$ST_UI_BOLD" NOC "$1"; }
st_section() { st_ui_emit "$ST_UI_CYAN" SECTION "$1"; }
st_info() { st_ui_emit "$ST_UI_CYAN" INFO "$1"; }
st_step() { st_ui_emit "$ST_UI_MAGENTA" STEP "$1"; }
st_ok() { st_ui_emit "$ST_UI_GREEN" OK "$1"; }
st_warn() { st_ui_emit "$ST_UI_YELLOW" WARN "$1"; }
st_error() { st_ui_emit "$ST_UI_RED" ERROR "$1"; }
