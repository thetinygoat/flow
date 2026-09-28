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
    # shims go in front of wherever the agents were installed.
    if [[ -o 'interactive' && -n "$FLOW_SURFACE_ID" && -z "$FLOW_AGENTS_DISABLED" ]]; then
        _flow_agents_init() {
            precmd_functions=(${precmd_functions:#_flow_agents_init})
            'builtin' 'unfunction' '_flow_agents_init'
            'builtin' 'local' dir="${TMPDIR:-/tmp}/flow-shims/$FLOW_SURFACE_ID"
            "$FLOW_FLW" shims "$dir" && 'builtin' 'export' PATH="$dir:$PATH"
        }
        'builtin' 'typeset' -ga precmd_functions
        precmd_functions+=(_flow_agents_init)
    fi
}
