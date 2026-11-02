# Flow adds this directory to XDG_DATA_DIRS only so that fish finds this
# file; programs started from the shell should see the user's value.
set --local flow_data_dir (string replace --regex -- '/fish/vendor_conf.d$' '' (status dirname))
set --local data_dirs (string split -- : "$XDG_DATA_DIRS")
if set --local index (contains --index -- $flow_data_dir $data_dirs)
    set --erase data_dirs[$index]
    if set --query data_dirs[1]
        set --global --export XDG_DATA_DIRS (string join -- : $data_dirs)
    else
        set --erase --global XDG_DATA_DIRS
    end
end

# Programs started from the shell must not resume the agent again.
set --local resume $FLOW_RESUME
set --erase FLOW_RESUME

# The first prompt comes after the user's config has set PATH, so the shims
# go in front of wherever the agents were installed. A restored terminal's
# agent then starts there, through the shims and into history. It runs before
# the prompt is drawn: fish asks the terminal about itself once it is, and an
# agent started from the command line would read the answer.
if status is-interactive; and set --query FLOW_SURFACE_ID FLOW_SHIMS; and not set --query FLOW_AGENTS_DISABLED
    set --global __flow_resume $resume
    function __flow_agents_init --on-event fish_prompt
        functions --erase __flow_agents_init
        set --local dir $FLOW_SHIMS/$FLOW_SURFACE_ID
        "$FLOW_FLW" shims $dir; and set --global --export --prepend PATH $dir
        if set --query __flow_resume[1]
            history append -- $__flow_resume 2>/dev/null
            eval $__flow_resume
        end
        set --erase __flow_resume
    end
end
