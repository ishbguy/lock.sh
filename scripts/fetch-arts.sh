#!/usr/bin/env bash
# Copyright (c) 2023 Herbert Shen <ishbguy@hotmail.com> All Rights Reserved.
# Released under the terms of the MIT License.

# source guard
[[ $FETCH_ARTS_SOURCED -eq 1 ]] && return
readonly FETCH_ARTS_SOURCED=1
readonly FETCH_ARTS_ABS_SRC="$(readlink -f "${BASH_SOURCE[0]}")"
readonly FETCH_ARTS_ABS_DIR="$(dirname "$FETCH_ARTS_ABS_SRC")"

# Utils
FETCH_ARTS_EXIT_CODE=0
warn() { echo -e "$@" >&2; ((++FETCH_ARTS_EXIT_CODE)); return ${WERROR:-1}; }
die() { echo -e "$@" >&2; exit $((++FETCH_ARTS_EXIT_CODE)); }
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

crawl_url() {
    local -n urls="$1" htmls="$2"
    local html="$(curl --silent "$3")"
    local -a dir_urls=($(htmlq -b "$ASCII_ART_URL" '#directory' -a href a 2>/dev/null <<<"$html"))

    if [[ ${dir_urls[*]} ]]; then
        for url in "${dir_urls[@]}"; do
            # website friendly to wait for a while
            read -rt 0.5; crawl_url "$1" "$2" "$url"
        done
    else
        urls+=("$3")
        htmls+=("$html")
    fi
}

fetch_arts() {
    local PROGNAME="$(basename "${BASH_SOURCE[0]}")"
    local VERSION="v0.0.1"
    local HELP=$(cat <<EOF
$PROGNAME $VERSION
$PROGNAME [-hvD] args
    
    -h  print this help message 
    -v  print version number
    -D  turn on debug mode

This program is released under the terms of the MIT License.
EOF
)
    local -A opts=() args=()
    pargs opts args 'hvD' "$@"
    shift $((OPTIND - 1))
    [[ ${opts[D]} ]] && set -x
    [[ ${opts[h]} ]] && usage && return 0
    [[ ${opts[v]} ]] && version && return 0

    require_tool curl htmlq awk

    local ASCII_ART_URL="https://www.asciiart.eu"
    local ASCII_ART_DIR="${FETCH_ARTS_ABS_DIR}/../asciiarts"
    local -a URLS=() HTMLS=() 

    crawl_url URLS HTMLS "$ASCII_ART_URL"

    for i in $(eval "echo {0..$((${#URLS[@]} - 1))}"); do
        local file="${ASCII_ART_DIR}/${URLS[$i]#$ASCII_ART_URL/}"
        local dir="$(dirname "$file")"

        [[ -d $dir ]] || mkdir -p "$dir"
        
        awk -v file="$file" '
        BEGIN { RS = "@@ascii-art-record-separator@@\n" ; FS = "\n" }
        {
            if ($0)
                print $0 > (file "-" NR-1 ".txt")
        }
        ' <<<"$(echo "${HTMLS[$i]}" | htmlq .asciiarts | htmlq -p pre \
            | sed -r -e 's#^<pre.*>#@@ascii-art-record-separator@@\n#g' -e '/<\/pre>$/d' \
            -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e 's/&amp;/\&/g')"
    done

}

is_sourced || fetch_arts "$@"

# vim:set ft=sh ts=4 sw=4:
