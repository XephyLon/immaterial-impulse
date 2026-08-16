#!/usr/bin/env bash
# Immaterial Impulse bootstrap installer.
#
# Fetch the whole suite and launch its installer with one command:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/XephyLon/immaterial-impulse/main/get.sh)
#
# Use the `bash <(curl ...)` form, NOT `curl ... | bash`: the installer is
# interactive (whiptail menu), and piping the script into bash would occupy
# stdin and break the prompts.
#
# The suite installer (`setup` + `sdata/`) needs the full repository tree, so
# this just clones it (to a stable location, reused for updates) and hands off.
#
# Overridable via env: IMI_REPO, IMI_REF (branch/tag/commit), IMI_DEST.
set -euo pipefail

REPO="${IMI_REPO:-https://github.com/XephyLon/immaterial-impulse}"
REF="${IMI_REF:-main}"
DEST="${IMI_DEST:-${XDG_DATA_HOME:-$HOME/.local/share}/immaterial-impulse/src}"

# The commit this script last installed. It is the only way to tell "this
# checkout is exactly what the updater put here" from "the user has committed
# in it" in a --depth 1 checkout: both HEAD and the incoming tip are grafted,
# so `merge-base --is-ancestor` has no history to walk and answers "no" for
# every checkout that is merely a few commits behind.
INSTALLED_REF="refs/imi/installed"

# The installer's whiptail menu takes over the terminal within seconds of this
# script printing anything, and the terminal is one the shell spawned, so a
# rescue has to leave a trail on disk as well as on screen.
RESCUE_LOG="$(dirname "$DEST")/rescued-local-work.log"

dgit() { git -C "$DEST" "$@"; }

announce() { printf '%s\n' "$@" | tee -a "$RESCUE_LOG"; }

# git refuses to write the stash's commits without an identity, and a machine
# being set up for the first time frequently has none configured. Borrowing an
# identity for one stash commit beats losing the work that commit holds.
stash_identity() {
  if dgit var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
    return
  fi
  printf '%s\n' -c "user.name=Immaterial Impulse installer" -c "user.email=imi@localhost"
}

# HEAD may be moved without asking only when it is the remote's own commit:
# either the one this script installed, or - in a full clone, where the answer
# is computable - an ancestor of the incoming tip.
head_came_from_remote() {
  local head="$1" target="$2" installed
  installed="$(dgit rev-parse --verify -q "$INSTALLED_REF" || true)"
  if [[ -n "$installed" && "$head" == "$installed" ]]; then
    return 0
  fi
  dgit merge-base --is-ancestor "$head" "$target" 2>/dev/null
}

# `checkout -f` + `reset --hard` are how this script guarantees the checkout
# really is $REF. They are also how it used to destroy, with no warning, work
# that exists nowhere else: commits the user made here, uncommitted edits, and
# untracked files the incoming tree happens to overwrite. Move all three
# somewhere git can hand back, then say where in words that outlive the
# installer's screen. Aborting instead would punish the overwhelmingly common
# case (a clean checkout, nothing to save) for the rare one.
preserve_local_work() {
  local head target short rescue_branch="" stash_message=""
  local -a at_risk=()
  local -a identity=()
  local -A incoming=()

  head="$(dgit rev-parse --verify -q HEAD || true)"
  [[ -n "$head" ]] || return 0
  target="$(dgit rev-parse FETCH_HEAD)"

  if [[ "$head" != "$target" ]] && ! head_came_from_remote "$head" "$target"; then
    short="$(dgit rev-parse --short "$head")"
    # Named for the commit rather than for the moment, so re-running the
    # updater against the same local work reuses the ref instead of littering
    # the checkout with one more every time.
    rescue_branch="imi-rescue/$short"
    dgit branch -f "$rescue_branch" "$head" >/dev/null
  fi

  while IFS= read -r -d '' path; do
    at_risk+=("$path")
  done < <(dgit diff --name-only -z HEAD --)

  # An untracked file is at risk only where the incoming tree carries a file of
  # the same name: `checkout -f` overwrites exactly those and leaves every
  # other untracked file alone. Stashing all of them would make a user's own
  # scratch files vanish out of the checkout on an update that never threatened
  # them.
  while IFS= read -r -d '' path; do
    incoming["$path"]=1
  done < <(dgit ls-tree -r --name-only -z "$target")
  while IFS= read -r -d '' path; do
    if [[ -n "${incoming[$path]:-}" ]]; then
      at_risk+=("$path")
    fi
  done < <(dgit ls-files --others --exclude-standard -z)

  if (( ${#at_risk[@]} > 0 )); then
    stash_message="Immaterial Impulse updater: work set aside before updating to $REF"
    mapfile -t identity < <(stash_identity)
    if ! dgit "${identity[@]}" stash push --include-untracked \
         --message "$stash_message" -- "${at_risk[@]}"; then
      echo "[ImI] Refusing to update: ${#at_risk[@]} file(s) in $DEST have changes" >&2
      echo "[ImI] that could not be stashed, and the update would overwrite them." >&2
      echo "[ImI] Save or commit them (or stash them by hand), then re-run." >&2
      exit 1
    fi
  fi

  if [[ -z "$rescue_branch" && -z "$stash_message" ]]; then
    return 0
  fi

  announce \
    "" \
    "============================================================" \
    "[ImI] $(date '+%Y-%m-%d %H:%M:%S') - local work in $DEST was set aside" \
    "------------------------------------------------------------" \
    "The updater makes that checkout match '$REF' exactly, which" \
    "overwrites whatever is in it. Nothing was thrown away:"
  if [[ -n "$rescue_branch" ]]; then
    announce \
      "" \
      "  Your commits are on the branch $rescue_branch" \
      "    git -C \"$DEST\" log $rescue_branch" \
      "    git -C \"$DEST\" checkout $rescue_branch"
  fi
  if [[ -n "$stash_message" ]]; then
    announce \
      "" \
      "  Your ${#at_risk[@]} changed/added file(s) are in the newest stash" \
      "    git -C \"$DEST\" stash list" \
      "    git -C \"$DEST\" stash pop"
  fi
  announce \
    "" \
    "This message is also saved in:" \
    "  $RESCUE_LOG" \
    "============================================================" \
    ""

  # The whiptail menu is about to replace everything above, so give a watching
  # user a chance to read it. No terminal, no prompt - the update still runs.
  if [[ -t 0 ]]; then
    read -r -p "[ImI] Press Enter to continue with the update ... " _ || true
  fi
}

if ! command -v git >/dev/null 2>&1; then
  echo "[ImI] git is required to fetch Immaterial Impulse. Install git and re-run." >&2
  exit 1
fi

if [[ -d "$DEST/.git" ]]; then
  echo "[ImI] Updating existing checkout at $DEST ..."
  git -C "$DEST" fetch --depth 1 origin "$REF"
  preserve_local_work
  git -C "$DEST" checkout -f "$REF" 2>/dev/null || git -C "$DEST" checkout -f FETCH_HEAD
  git -C "$DEST" reset --hard FETCH_HEAD
else
  echo "[ImI] Cloning $REPO ($REF) into $DEST ..."
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 --branch "$REF" "$REPO" "$DEST" 2>/dev/null \
    || git clone "$REPO" "$DEST"
fi
git -C "$DEST" update-ref "$INSTALLED_REF" HEAD

cd "$DEST"
echo "[ImI] Launching the installer (source: $DEST) ..."
exec ./setup "$@"
