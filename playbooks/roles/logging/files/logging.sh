declare -g PREV_COMMAND=""
declare -g PREV_HISTORY_LINE=""
declare -g LAST_HISTCMD=0

log_command() {
    [[ "$BASH_COMMAND" == "$PREV_COMMAND" ]] && return
    [[ -z "$BASH_COMMAND" ]] && return
    PREV_COMMAND="$BASH_COMMAND"
    if [[ "$HISTCMD" -eq 1 ]]; then
        CURR_LINE="$(history 1)"
        [[ "$CURR_LINE" == "$PREV_HISTORY_LINE" ]] && return
        PREV_HISTORY_LINE="$CURR_LINE"
    else
        [[ $HISTCMD -le $LAST_HISTCMD ]] && return
        LAST_HISTCMD=${HISTCMD:-0}
    fi
    TS=$(date "+%Y-%m-%d %H:%M:%S")
    USER=$(whoami)
    PWD=$(pwd)
    HOST=$(hostname)
    FROM=$(who am i | awk '{ gsub(/[()]/,"",$5); print $5 }')
    LOG_LINE="$USER ${FROM:-unknown} $PWD: $BASH_COMMAND"
    echo "$LOG_LINE" | logger -t terminal_command
}

trap log_command DEBUG
