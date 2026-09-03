# Use the generated color scheme. Inside tmux only the pane-safe file goes to
# the pane: the full one carries OSC 10/11/12, which tmux 3.4+ adopts as the
# pane's OWN default colours and then paints opaque, every cell - the rule
# applycolor.sh already follows when it pushes into pane ttys (AGENT.md, "A
# tmux pane never receives the terminal's default colours").

_imi_seq=~/.local/state/quickshell/user/generated/terminal/sequences.txt
if [ -n "$TMUX" ]; then
    _imi_seq=~/.local/state/quickshell/user/generated/terminal/sequences-pane.txt
fi
if [ -f "$_imi_seq" ]; then
    cat "$_imi_seq"
fi
unset _imi_seq
