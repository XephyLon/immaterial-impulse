# Review sandbox

A nested Hyprland with its own D-Bus and XDG dirs, running a worktree's shell
against the shipped defaults, so a change can be driven and captured without
touching the live session. Every feature PR is reviewed this way (AGENT.md:
sandbox drive + captures, then a reviewer scoring perf / look & feel / design
cohesion, iterate until every axis is >= 8.5). Never capture the live screen.

    tests/sandbox/sandbox_shell.sh start <shell-root> <sandbox-dir> [overrides.json]
    source <sandbox-dir>/env            # hyprctl, qs -c imi ipc, grim, wtype now talk to the sandbox
    tests/sandbox/sandbox_shell.sh shot <sandbox-dir> <out.png>
    tests/sandbox/sandbox_shell.sh stop <sandbox-dir>     # from OUTSIDE the sandbox

`stop` ends everything the sandbox started - the shell first, then its helpers and the session's
D-Bus - found by `IMI_SANDBOX_SESSION=<sandbox-dir>`, which only the session carries (the env file
does not, so a terminal that sourced it is never matched). It needs no env file, never kills a pid
from one on its own, removes only a run dir `start` made (`/tmp/imi-sb-XXXXXX`, unmounting any FUSE
mount left in it), refuses to run from inside the sandbox, and says how many processes it ended and
whether any are left - exiting non-zero if any are. The sandbox dir is canonicalised by both
commands, so any spelling of it names the same sandbox. A directory is a sandbox only if it holds
the `.imi-sandbox` sentinel `start` writes - never because of the names of the files in it. `start`
on an existing sandbox dir stops that sandbox first and gives up if it cannot; it will not wipe a
non-empty directory without the sentinel; and a start that fails ends the session it began.
A sandbox made before the sentinel existed is refused like any other directory: `stop` it, then
remove it. `SANDBOX_START_WAIT` (whole seconds) and `SANDBOX_STOP_KILL` (`true` only) are hooks for
`test_sandbox_shell.py`; both are validated and announce themselves when set. Before these, every stop left the
shell's helpers running, and they piled up (`test_sandbox_shell.py`).

- `<shell-root>` is `dots/.config/quickshell/imi` of the worktree under review. It is SYMLINKED,
  not copied: editing under `<sandbox-dir>/config/quickshell/imi/` edits the repo. Probe patches go
  in an rsync'd scratch copy.
- Overrides: `{"config": {...}, "states": {...}}` merged over `defaults/config.json`; `states`
  seeds `states.json`. The shell hot-reloads QML edits and config writes.
- `apply_overrides.sh <sandbox-dir> <overrides.json>` merges into the RUNNING sandbox's config.
  The appearance domain lives in `config.d/appearance.json`, wrapped as `{"appearance": {...}}`;
  a merge into the wrong file is silently ignored - this script knows the split.
- `crops_by_layout.sh <sandbox-dir> <shot.png> <name>` crops the dock strip, the corners and a
  downscaled whole from the shell's own layout (the `quickshell:background` layer in
  `hyprctl layers -j` times the monitor scale). The nested output resizes with the parent's
  tiling and the layout can lag it; never crop by image size.
- Cursor and window dispatchers use the nested compositor's Lua syntax:
  `hyprctl dispatch 'hl.dsp.cursor.move({x=..., y=...})'`. The classic `movecursor` prints
  nothing and does nothing. Kill test windows by the `pid` in `hyprctl clients -j`.
- `qs -c imi ipc call settings page "<page id>[:<section>]"` opens Settings on a page (go via
  another page first for a section jump). Test windows: `setsid -f kitty --title x`.
- `fake_openai.py <port>` is an OpenAI + Ollama-shaped fake for AI features (run on 11434 so
  `ollama list` discovery sees it; free the port before a suite).
- `keepboth.py` resolves a CHANGELOG merge conflict by keeping both sides of every hunk
  (stacked branches all add Unreleased lines).
- Failure modes: `grim` hangs when the nested output stops producing frames (occluded or after a
  stall, or the PARENT display DPMS-off) - restart the sandbox; a `Monitor FALLBACK 0x0` line means
  the same. One sandbox at a time. To measure the shell's CPU, find it by the session marker in
  `/proc/<pid>/environ`, never with `pgrep -n`: that picks the newest matching process, which need
  not be this sandbox's shell. Never delete a sandbox dir by hand - `stop` it (a session whose dir
  is gone keeps running). A failed QML load kills the shell: read the LAST `caused by` line in
  `<sandbox-dir>/qs.log`.
