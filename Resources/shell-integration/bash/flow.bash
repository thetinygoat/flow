# Flow cannot load this into bash by itself. To have agents started through
# Flow's shims, end ~/.bashrc or ~/.bash_profile with
#
#   [ -n "$FLOW_FLW" ] && source "${FLOW_FLW%/*}/../Resources/shell-integration/bash/flow.bash"
#
# The first prompt comes after the user's config has set PATH, so the shims
# go in front of wherever the agents were installed.
if [[ $- == *i* && -n "$FLOW_SURFACE_ID" && -z "$FLOW_AGENTS_DISABLED" ]]; then
    __flow_agents_init() {
        PROMPT_COMMAND=${PROMPT_COMMAND/__flow_agents_init;/}
        unset -f __flow_agents_init
        local dir="${TMPDIR:-/tmp}/flow-shims/$FLOW_SURFACE_ID"
        "$FLOW_FLW" shims "$dir" && PATH="$dir:$PATH"
    }
    PROMPT_COMMAND="__flow_agents_init;${PROMPT_COMMAND}"
fi
