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
calc_draw_pos() {
    local lines="$(tput lines)" cols="$(tput cols)"
    if [[ $lines -lt $1 && $cols -lt $2 ]]; then
        echo 0 0
    elif [[ $lines -lt $1 ]]; then
        echo 0 "$(((cols - $2) / 2))"
    elif [[ $cols -lt $2 ]]; then
        echo "$(((lines - $1) / 2))" 0
    else
        echo "$(((lines - $1) / 2))" "$(((cols - $2) / 2))"
    fi
}
lock_draw_pos() {
    tput cup "$1" "$2"; shift 2
    echo "$*"
}
lock_draw() {
    local msg="$*"
    local -a cur_pos=($(calc_draw_pos $(str_sizeof "$msg")))
    local IFS= ; while read -r line; do
        lock_draw_pos "$((cur_pos[0]++))" "${cur_pos[1]}" "$line"
    done <<<"$msg"
}
lock_draw_clear() {
    local msg="$*"
    local -a cur_pos=($(calc_draw_pos $(str_sizeof "$msg")))
    local IFS= ; while read -r line; do
        lock_draw_pos "$((cur_pos[0]++))" "${cur_pos[1]}" "${line//?/ }"
    done <<<"$msg"
}
lock_screen() {
    local n=0 ctx last_ctx
    local -a msgbox=("$@")
    local slide_time="$(date)"
    while true; do
        if [[ $(date_cmp "$(date)" "$slide_time") -ge ${LOCK_SLIDE_TIME} ]]; then
            slide_time="$(date)"
            [[ $((++n)) -lt ${#@} ]] || n=0
            [[ ${opts[e]} == "S" ]] && ctx="$(eval echo \""${msgbox[n]}"\")"
            tput clear
        fi
        if [[ ${opts[e]} ]]; then
            if [[ ${opts[e]} == "S" ]]; then
                [[ $last_ctx ]] || ctx="$(eval echo \""${msgbox[n]}"\")"
            else
                ctx="$(eval echo \""${msgbox[n]}"\")"
            fi
            [[ $ctx != "$last_ctx" ]] && last_ctx="$ctx" && tput clear
            lock_draw "$ctx"
        else
            lock_draw "${msgbox[n]}"
        fi
        if read -sr -N 1 -t 0.1; then
            if [[ -n ${opts[l]} && $(date_cmp "$(date)" "$LOCK_START_TIME") -ge ${LOCK_LOGIN_TIME} ]]; then
                lock_login "Enter your password:" && break || tput civis
            else
                break
            fi
        fi
    done
}
lock_term() {
    # init and setting the terminal environment
    tput init; tput smcup; tput clear; tput civis
    trap 'tput clear' WINCH
    lock_screen "$@"
    tput rmcup; tput cnorm
}
lock_run() {
    (eval "$*")
    # invoke lock_login if LOCK_LOGIN_TIME out and run with -l option
    if [[ $(date_cmp "$(date)" "$LOCK_START_TIME") -ge ${LOCK_LOGIN_TIME} ]]; then
        while [[ ${opts[l]} ]]; do
            lock_login "Enter your password:" && break
            (eval "$*")
        done
    fi
}

lock() {
    local PROGNAME="$(basename "${BASH_SOURCE[0]}")"
    local VERSION="v0.7.0"
    local HELP=$(cat <<EOF
$PROGNAME $VERSION
$PROGNAME [-leAhvD] [-c cmd|-a name|-d dir|-t sec|-s sec|-S sec] [args...]
    
    [args..]        Show the args string on lock screen
    -c <cmd>        Run the [cmd] as the lock screen command
    -a <name>       Show the <name> ascii art on lock screen
    -d <dir>        Specify the ascii art director, work with -a option
    -e              Make shell expansion when lock screen
    -l              Need to login to unlock the screen
    -t <sec>        Specify <sec> seconds timer to invoke the login
    -s <sec>        Slideshow mode, slide every <sec> seconds
    -S <sec>        Shuffle slideshow mode, slide every <sec> seconds
    -AS <sec>       Shuffle slideshow with local ascii arts every <sec> seconds
    -h              Print this help message
    -v              Print version number
    -D              Turn on debug mode

For examples:

    lock.sh                         # Run without opts and args will show a login screen
    lock.sh "Hello world!"          # Show the 'Hello world!' string on lock screen
    lock.sh -c cmatrix              # Run cmatrix as lock screen
    lock.sh -l -c cmatrix           # Run cmatrix as lock screen and need to login to unlock
    lock.sh -l -t 10 cmatrix        # Run cmatrix then will invoke login if run over 10 seconds
    lock.sh -a zebra                # Show the 'zebra' ascii art on lock screen
    lock.sh -d art -a zebra         # Find 'zebra' ascii art in 'art' directory and
                                    # show it on the lock screen
    lock.sh -s 5 one two            # Slide every 5 seconds
    lock.sh -S 5                    # Shuffle every 5 seconds without args, it will try fortune
                                    # by default, or will invoke login screen
    lock.sh -S 5 one two three      # Shuffle every 5 seconds with args
    lock.sh -AS 5                   # Shuffle every 5 seconds with local ascii arts
    lock.sh -e '\$(date +%H:%M)'     # Dynamic expansion the date output

This program is released under the terms of the MIT License.
EOF
)
    local -A opts=() args=()
    pargs opts args 'lehvADc:a:d:s:S:t:' "$@"
    shift $((OPTIND - 1))
    [[ ${opts[D]} ]] && set -x
    [[ ${opts[h]} ]] && usage && return 0
    [[ ${opts[v]} ]] && version && return 0

    require_tool dialog tput find shuf

    # ignore termination and terminal job controlling signals
    trap 'true' TERM INT QUIT HUP
    trap 'true' TSTP TTIN TTOU

    # configure default variables
    local LOCK_ART_DIR="${args[d]:-${LOCK_ART_DIR:-$LOCK_ABS_DIR/../asciiarts}}"
    local LOCK_LOGIN_TIME="${args[t]:-${LOCK_LOGIN_TIME:-60}}"
    local LOCK_SLIDE_TIME="${args[S]:-${args[s]:-${LOCK_SLIDE_TIME:-60}}}"
    local LOCK_START_TIME="$(date)"

    if [[ ${opts[c]} ]]; then
        lock_run "${args[c]}"
    elif [[ ${opts[a]} ]]; then
        [[ -d $LOCK_ART_DIR && -e $LOCK_ART_DIR/${args[a]} ]] || \
            die "$PROGNAME: $LOCK_ART_DIR/${args[a]}: No such file or directory"
        lock_term "$(cat "$LOCK_ART_DIR/${args[a]}")"
    elif [[ ${opts[S]} ]]; then
        if [[ $* ]]; then
            local -a args_array=("$@") shuf_array=()
            for i in $(shuf -e $(eval "echo {0..$((${#args_array[@]} - 1))}")); do
                shuf_array+=("${args_array[$i]}")
            done
            lock_term "${shuf_array[@]}"
        elif [[ ${opts[A]} ]]; then
            local -a ascii_arts=()
            for f in $(find $LOCK_ART_DIR -type f | shuf -n 25 -); do
                ascii_arts+=("$(cat "$f")")
            done
            lock_term "${ascii_arts[@]}"
        elif has_tool fortune; then
            opts[e]=S; lock_term '$(fortune)'
        else
            # lock with -S but witout args, invoke lock_login instead
            while true; do
                lock_login "Enter your password:" && break
            done
        fi
    elif [[ ${opts[s]} && $* ]]; then
        lock_term "$@"
    elif [[ $* ]]; then
        lock_term "$*"
    elif has_tool fortune; then
        lock_term "$(fortune)"
    else
        # lock without anything will invoke lock_login as default
        while true; do
            lock_login "Enter your password:" && break
        done
    fi
}

is_sourced || lock "$@"

# vim:set ft=sh ts=4 sw=4:
