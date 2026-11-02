# Flow cannot load this into bash by itself. To have agents started through
# Flow's shims, end ~/.bashrc or ~/.bash_profile with
#
#   [ -n "$FLOW_FLW" ] && source "${FLOW_FLW%/*}/../Resources/shell-integration/bash/flow.bash"
#
# The first prompt comes after the user's config has set PATH, so the shims
# go in front of wherever the agents were installed. A restored terminal's
# agent then starts there, through the shims and into history. Bash offers no
# way to run a line as if typed, so it runs before the prompt is drawn.
if [[ $- == *i* && -n "$FLOW_SURFACE_ID" && -n "$FLOW_SHIMS" && -z "$FLOW_AGENTS_DISABLED" ]]; then
    __flow_resume=$FLOW_RESUME
    __flow_agents_init() {
        PROMPT_COMMAND=${PROMPT_COMMAND/__flow_agents_init;/}
        unset -f __flow_agents_init
        local dir="$FLOW_SHIMS/$FLOW_SURFACE_ID"
        "$FLOW_FLW" shims "$dir" && PATH="$dir:$PATH"
        if [[ -n "$__flow_resume" ]]; then
            history -s "$__flow_resume"
            eval "$__flow_resume"
        fi
        unset __flow_resume
    }
    PROMPT_COMMAND="__flow_agents_init;${PROMPT_COMMAND}"
fi
# Programs started from the shell must not resume the agent again.
unset FLOW_RESUME
