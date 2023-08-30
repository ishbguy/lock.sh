#!/usr/bin/env bash
# Copyright (c) 2023-present Herbert Shen <ishbguy@hotmail.com> All Rights Reserved.
# Released under the terms of the MIT License.

# source guard
[[ $LOCK_SOURCED -eq 1 ]] && return
readonly LOCK_SOURCED=1
readonly LOCK_ABS_SRC="$(readlink -f "${BASH_SOURCE[0]}")"
readonly LOCK_ABS_DIR="$(dirname "$LOCK_ABS_SRC")"

# Utils
LOCK_EXIT_CODE=0
warn() { echo -e "$@" >&2; ((++LOCK_EXIT_CODE)); return ${WERROR:-1}; }
die() { echo -e "$@" >&2; exit $((++LOCK_EXIT_CODE)); }
debug() { [[ $DEBUG == 1 ]] && echo "$@" || true; }
usage() { echo -e "$HELP"; }
version() { echo -e "$PROGNAME $VERSION"; }
defined() { declare -p "$1" &>/dev/null; }
definedf() { declare -f "$1" &>/dev/null; }
is_sourced() { [[ -n ${FUNCNAME[1]} && ${FUNCNAME[1]} != "main" ]]; }
is_array() { local -a def=($(declare -p "$1" 2>/dev/null)); [[ ${def[1]} =~ a ]]; }
is_map() { local -a def=($(declare -p "$1" 2>/dev/null)); [[ ${def[1]} =~ A ]]; }
has_tool() { hash "$1" &>/dev/null; }
ensure() {
    local cmd="$1"; shift
    local -a info=($(caller 0))
    (eval "$cmd" &>/dev/null) || \
       die "${info[2]}:${info[0]}:${info[1]}:${FUNCNAME[0]} '$cmd' failed. " "$@"
}
date_cmp() { echo "$(($(date -d "$1" +%s) - $(date -d "$2" +%s)))"; }
tmpfd() { basename <(:); }
pargs() {
    ensure "[[ $# -ge 3 ]]" "Need OPTIONS, ARGUMENTS and OPTSTRING"
    ensure "[[ -n $1 && -n $2 && -n $3 ]]" "Args should not be empty."
    ensure "is_map $1 && is_map $2" "OPTIONS and ARGUMENTS should be map."

    local -n __opt="$1"
    local -n __arg="$2"
    local optstr="$3"
    shift 3

    OPTIND=1
    while getopts "$optstr" opt; do
        [[ $opt == ":" || $opt == "?" ]] && die "$HELP"
        __opt[$opt]=1
        __arg[$opt]="$OPTARG"
    done
    shift $((OPTIND - 1))
}
trap_push() {
    ensure "[[ $# -ge 2 ]]" "Usage: trap_push 'cmds' SIGSPEC..."
    local cmds="$1"; shift
    for sig in "$@"; do
        defined "trap_$sig" || declare -ga "trap_$sig"
        local -n ts="trap_$sig"
        ts+=("$cmds")
        if [[ $sig == RETURN ]]; then
            trap "trap '$cmds; trap_pop RETURN' RETURN" RETURN 
        else
            trap "$cmds" "$sig"
        fi
    done
}
trap_pop() {
    ensure "[[ $# -ge 1 ]]" "Usage: trap_pop SIGSPEC..."
    for sig in "$@"; do
        defined "trap_$sig" || declare -ga "trap_$sig"
        local -n ts="trap_$sig"
        local cmds
        # pop cmds
        ts=("${ts[@]:0:$((${#ts[@]}-1))}")
        [[ ${#ts[@]} -gt 0 ]] && cmds="${ts[-1]}"
        if [[ $sig == RETURN ]]; then
            trap "trap '$cmds' RETURN" RETURN
        else
            trap "$cmds" "$sig"
        fi
    done
}
require() {
    ensure "[[ $# -gt 2 ]]" "Not enough args."
    ensure "definedf $1" "$1 should be a defined func."

    local -a miss
    local cmd="$1"
    local msg="$2"
    shift 2
    for obj in "$@"; do
        "$cmd" "$obj" || miss+=("$obj")
    done
    [[ ${#miss[@]} -eq 0 ]] || die "$msg: ${miss[*]}."
}
require_var() { require defined "You need to define vars" "$@"; }
require_func() { require definedf "You need to define funcs" "$@"; }
require_tool() { require has_tool "You need to install tools" "$@"; }
inicfg() { require_tool git; git config --file "$@"; }

check_password() { echo "$1" | su -c true - "$USER" &>/dev/null; }
lock_login() {
    dialog --clear --erase-on-exit --ascii-lines --output-fd "$1" \
        --passwordbox "Enter your password:" 10 40
    echo >&"$1"
    read -ru "$1" PASS
    check_password "$PASS"
}

lock() {
    local PROGNAME="$(basename "${BASH_SOURCE[0]}")"
    local VERSION="v0.1.0"
    local HELP=$(cat <<EOF
$PROGNAME $VERSION
$PROGNAME [-lhvD] [args...]
    
    args  will run as the lock screen command
    -l    need to login to unlock the screen
    -h    print this help message 
    -v    print version number
    -D    turn on debug mode

This program is released under the terms of the MIT License.
EOF
)
    local -A opts=() args=()
    pargs opts args 'lhvD' "$@"
    shift $((OPTIND - 1))
    [[ ${opts[D]} ]] && set -x
    [[ ${opts[h]} ]] && usage && return 0
    [[ ${opts[v]} ]] && version && return 0

    require_tool dialog

    # ignore termination and terminal job controlling signals
    trap 'true' SIGTERM SIGINT SIGQUIT SIGHUP
    trap 'true' SIGTSTP SIGTTIN SIGTTOU

    export DIALOGRC="$LOCK_ABS_DIR/dialogrc"

    # make a fifo file descriptor to store the user password
    local passfd="$(tmpfd)"
    local passfile="$(mktemp -u)"
    mkfifo "$passfile" || return 1
    eval "exec $passfd<>$passfile" && rm -rf "$passfile" || return 1

    local start_time="$(date)"
    if [[ $* ]]; then
        (eval "$@")
        # invoke lock_login if LOCK_LOGIN_TIME out and run with -l option
        if [[ $(date_cmp "$(date)" "$start_time") -gt $LOCK_LOGIN_TIME ]]; then
            while [[ ${opts[l]} ]]; do
                lock_login "$passfd" && break
                (eval "$@")
            done
        fi
    else
        # lock without cmd will invoke lock_login as default
        while true; do
            lock_login "$passfd" && break
        done
    fi
}

is_sourced || lock "$@"

# vim:set ft=sh ts=4 sw=4:
