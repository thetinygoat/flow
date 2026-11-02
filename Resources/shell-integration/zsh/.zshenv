# Flow points ZDOTDIR here so that zsh runs this first; the rest of startup
# must read the user's own files.
if [[ -n "${FLOW_ZSH_ZDOTDIR+X}" ]]; then
    'builtin' 'export' ZDOTDIR="$FLOW_ZSH_ZDOTDIR"
    'builtin' 'unset' 'FLOW_ZSH_ZDOTDIR'
else
    'builtin' 'unset' 'ZDOTDIR'
fi

# Quoted builtins keep the user's aliases out of this file.
{
    'builtin' 'typeset' _flow_file="${ZDOTDIR-$HOME}/.zshenv"
    [[ ! -r "$_flow_file" ]] || 'builtin' 'source' '--' "$_flow_file"
} always {
    'builtin' 'unset' '_flow_file'
    # The first prompt comes after the user's config has set PATH, so the
    # shims go in front of wherever the agents were installed. A restored
    # terminal's agent then starts as if typed there, through the shims and
    # into history. Only the line editor can run a line as typed.
    if [[ -o 'interactive' && -n "$FLOW_SURFACE_ID" && -n "$FLOW_SHIMS" && -z "$FLOW_AGENTS_DISABLED" ]]; then
        'builtin' 'typeset' -g _flow_resume="$FLOW_RESUME"
        _flow_agents_init() {
            precmd_functions=(${precmd_functions:#_flow_agents_init})
            'builtin' 'unfunction' '_flow_agents_init'
            'builtin' 'local' dir="$FLOW_SHIMS/$FLOW_SURFACE_ID"
            "$FLOW_FLW" shims "$dir" && 'builtin' 'export' PATH="$dir:$PATH"
            if [[ -n "$_flow_resume" ]]; then
                'builtin' 'autoload' -Uz add-zle-hook-widget
                add-zle-hook-widget line-init _flow_resume_line
            else
                'builtin' 'unset' '_flow_resume'
            fi
        }
        _flow_resume_line() {
            add-zle-hook-widget -d line-init _flow_resume_line
            BUFFER="$_flow_resume"
            'builtin' 'unset' '_flow_resume'
            'builtin' 'zle' accept-line
        }
        'builtin' 'typeset' -ga precmd_functions
        precmd_functions+=(_flow_agents_init)
    fi
    # Programs started from the shell must not resume the agent again.
    'builtin' 'unset' 'FLOW_RESUME'
}
