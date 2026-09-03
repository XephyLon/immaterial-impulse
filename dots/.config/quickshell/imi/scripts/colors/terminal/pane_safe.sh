#!/usr/bin/env bash
# The terminal colour sequences, made safe for a tmux PANE.
#
# applycolor.sh pushes sequences.txt into every interactive pty. A tmux pane's
# pty is one of those, and tmux (3.4+) adopts an OSC 10/11/12 it receives there
# as that pane's own default foreground/background/cursor - and from then on
# paints the pane's background EXPLICITLY, every cell, instead of leaving it to
# the terminal. In kitty that is the difference between a translucent window
# and a solid slab: kitty applies background_opacity only to its default
# background colour. Measured: `#{pane_bg}` was #1b1b17 on every pane, and the
# pane went opaque while the padding around it stayed blurred.
#
# So a pane gets the palette (OSC 4 - indexed colours apps do use) and a RESET
# of the three defaults (OSC 110/111/112), so a pane coloured by an earlier
# push recovers too. The defaults themselves reach the pane through the outer
# terminal, which receives the full sequences on the tmux client's own pty.
#
# stdin: the generated sequences. stdout: the pane-safe sequences.
sed -E $'s/\x1b\\](10|11|12|13|17|19|708);[^\x1b]*\x1b\\\\//g'
printf '\033]110\033\\\033]111\033\\\033]112\033\\'
