# CLAUDE.md

**Before doing any work in this repository, read `AGENT.md` and then `CONTRIBUTING.md` —
sequentially, each in full, top to bottom.** Grep hits and section jumps do not count as having
read them: the rules that get broken are the ones adjacent to the section someone jumped to, and
this repo has shipped regressions exactly that way — 5d4bfa773 ("feat(wallpaperEngine): reinstate
activeStill, this time with a writer") restored a removed config field without its removal ever
being read, and re-armed the bug the removal fixed. Re-read both files after a context compaction.

Two mechanical rules guard those files (details in `CONTRIBUTING.md` → "Keep AGENT.md in sync"):

- **Every point added to `AGENT.md` or `CONTRIBUTING.md` must cite the commit that motivated it**
  as `<sha> ("<subject>")`. `tests/lint_doc_citations.py` fails the suite on any citation that
  resolves to nothing.
- **Every PR body must carry a `Docs:` receipt line** — `Docs: updated <file> §<section>` or
  `Docs: not needed — <reason>`. CI rejects PRs without one.
