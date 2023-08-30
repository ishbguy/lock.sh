#!/usr/bin/env bash

# for debug
#set -x

TMUX_LOCK_CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}"  )" && pwd  )"

# Get the absolute path to the users configuration file of TMux.
# This includes a prioritized search on different locations.
#
get_user_tmux_conf() {
    # Define the different possible locations.
    xdg_location="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
    default_location="$HOME/.tmux.conf"

    # Search for the correct configuration file by priority.
    if [ -f "$xdg_location"  ]; then
        echo "$xdg_location"
    else
        echo "$default_location"
    fi
}

tmux_conf_contents() {
    user_config=$(get_user_tmux_conf)
    cat /etc/tmux.conf "$user_config" 2>/dev/null
}

tmux_get_option() {
    local option_value
    option_value="$(tmux show-options -gqv "$1")"
    [[ -n $option_value ]] || option_value="$2"
    echo "$option_value"
}

tmux_get_env() {
    local env_value
    env_value="$(tmux show-environment -g "$1" 2>/dev/null | cut -d= -f2)"
    [[ -n $env_value ]] || env_value="$2"
    echo "$env_value"
}

main() {
    tmux set-option -g lock-after-time "$(tmux_get_option '@lock-after-time' "$(tmux_get_option 'lock-after-time')")"
    tmux set-option -g lock-command "$TMUX_LOCK_CURRENT_DIR/scripts/lock.sh $(tmux_get_option '@lock-command' "$(tmux_get_option 'lock-command')")"
    tmux bind-key "$(tmux_get_option '@lock-key' 'M-l')" lock
}

main
