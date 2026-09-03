# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != "linux"
        starship init fish | source
        enable_transience
    end
    
    # Colors. Inside tmux only the pane-safe file goes to the pane: the full
    # one carries OSC 10/11/12, which tmux 3.4+ adopts as the pane's OWN
    # default colours and then paints opaque - the rule applycolor.sh follows
    # when it pushes into pane ttys (AGENT.md, "A tmux pane never receives
    # the terminal's default colours").
    set -l imi_seq ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    if set -q TMUX
        set imi_seq ~/.local/state/quickshell/user/generated/terminal/sequences-pane.txt
    end
    if test -f $imi_seq
        cat $imi_seq
    end

    # Aliases
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    alias q 'qs -c imi'
    if test "$TERM" != "linux"
        alias ls 'eza --icons=auto'
    end
    if test "$TERM" = "xterm-kitty"
        alias ssh 'kitten ssh'
    end
end
