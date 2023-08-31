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

check_password() {
    [[ -n $1 ]] || return 1
    echo "$1" | su -c true - "${2:-$USER}" &>/dev/null
}
lock_login() {
    # make a fifo file descriptor to store the user password
    local passfd="$(tmpfd)"
    local passfile="$(mktemp -u)"
    mkfifo "$passfile" || return 1
    eval "exec $passfd<>$passfile" && rm -rf "$passfile" || return 1

    DIALOGRC="$LOCK_ABS_DIR/dialogrc" dialog --clear --erase-on-exit --ascii-lines \
        --output-fd "$passfd" --passwordbox "$*" 10 40
    echo >&"$passfd"
    read -ru "$passfd" PASS
    check_password "$PASS"
}
str_sizeof() {
        local string=$1 max_lines=0 max_cols=0
        while read -r line; do
            ((++max_lines))
            [[ ${#line} -gt $max_cols ]] && max_cols="${#line}"
        done <<<"$string"
        echo "$max_lines" "$max_cols"
}
cal_start_pos() {
    echo "$((($(tput lines) - $1) / 2))" "$((($(tput cols) - $2) / 2))"
}
lock_draw() {
    local msg=$1 x=$2 y=$3
    local IFS= ; while read -r line; do
        tput cup "$((x++))" "$y"
        echo "$line"
    done <<<"$msg"
}

lock() {
    local PROGNAME="$(basename "${BASH_SOURCE[0]}")"
    local VERSION="v0.3.0"
    local HELP=$(cat <<EOF
$PROGNAME $VERSION
$PROGNAME [-lhvD] [cmd|-a name|-d dir|-s string]
    
    [cmd]           Run the [cmd] as the lock screen command
    -a <name>       Show the <name> ascii art on lock screen
    -d <dir>        Specify the ascii art director, work with -a option
    -s <string>     Show the <string> on lock screen
    -l              Need to login to unlock the screen
    -h              Print this help message
    -v              Print version number
    -D              Turn on debug mode

For examples:

    lock.sh                     # Run without opts and args will show a login screen
    lock.sh cmatrix             # Run cmatrix as lock screen
    lock.sh -l cmatrix          # Run cmatrix as lock screen and need to login to unlock
    lock.sh -a zebra            # Show the 'zebra' ascii art on lock screen
    lock.sh -d art -a zebra     # Find 'zebra' ascii art in 'art' director and
                                # show it on the lock screen
    lock.sh -s "Hello world!"   # Show the 'Hello world!' string on lock screen

This program is released under the terms of the MIT License.
EOF
)
    local -A opts=() args=()
    pargs opts args 'lhvDa:d:s:' "$@"
    shift $((OPTIND - 1))
    [[ ${opts[D]} ]] && set -x
    [[ ${opts[h]} ]] && usage && return 0
    [[ ${opts[v]} ]] && version && return 0

    require_tool dialog

    # ignore termination and terminal job controlling signals
    trap 'true' SIGTERM SIGINT SIGQUIT SIGHUP
    trap 'true' SIGTSTP SIGTTIN SIGTTOU

    local start_time="$(date)"
    if [[ $* ]]; then
        (eval "$@")
        # invoke lock_login if LOCK_LOGIN_TIME out and run with -l option
        if [[ $(date_cmp "$(date)" "$start_time") -gt ${LOCK_LOGIN_TIME:-60} ]]; then
            while [[ ${opts[l]} ]]; do
                lock_login "Enter your password:" && break
                (eval "$@")
            done
        fi
    elif [[ ${opts[s]} ]]; then
        local -a str_size=($(str_sizeof "${args[s]}"))
        local -a cur_pos=($(cal_start_pos "${str_size[0]}" "${str_size[1]}"))

        # init and setting the terminal environment
        tput init; tput smcup; tput clear; tput civis

        (lock_draw "${args[s]}" "${cur_pos[0]}" "${cur_pos[1]}"; read -sr)
        # invoke lock_login if LOCK_LOGIN_TIME out and run with -l option
        if [[ $(date_cmp "$(date)" "$start_time") -gt ${LOCK_LOGIN_TIME:-60} ]]; then
            while [[ ${opts[l]} ]]; do
                lock_login "Enter your password:" && break
                (lock_draw "${args[s]}" "${cur_pos[0]}" "${cur_pos[1]}"; read -sr)
            done
        fi
        tput rmcup
    elif [[ ${opts[a]} ]]; then
        local art_dir="${args[d]:-${LOCK_ART_DIR:-$LOCK_ABS_DIR/../../arttime/share/arttime/textart}}"
        [[ -d $art_dir && -e $art_dir/${args[a]} ]] || return 1

        local ascii_art="$(cat "$art_dir/${args[a]}")"
        local -a str_size=($(str_sizeof "$ascii_art"))
        local -a cur_pos=($(cal_start_pos "${str_size[0]}" "${str_size[1]}"))

        # init and setting the terminal environment
        tput init; tput smcup; tput clear; tput civis

        (lock_draw "$ascii_art" "${cur_pos[0]}" "${cur_pos[1]}"; read -sr)
        # invoke lock_login if LOCK_LOGIN_TIME out and run with -l option
        if [[ $(date_cmp "$(date)" "$start_time") -gt ${LOCK_LOGIN_TIME:-60} ]]; then
            while [[ ${opts[l]} ]]; do
                lock_login "Enter your password:" && break
                (lock_draw "$ascii_art" "${cur_pos[0]}" "${cur_pos[1]}"; read -sr)
            done
        fi
        tput rmcup
    else
        # lock without cmd will invoke lock_login as default
        while true; do
            lock_login "Enter your password:" && break
        done
    fi
}

is_sourced || lock "$@"

# vim:set ft=sh ts=4 sw=4:
