# Partitioning AGENT.md

Status: proposed, not started. Queued 2026-08-27.

## The problem, measured

`AGENT.md` is **5,714 lines / 471 KB ≈ 118,000 tokens**. `CONTRIBUTING.md`
adds 473 lines. Every agent brief in this project — and `CONTRIBUTING.md`
itself — says to read both **in full, top to bottom, before touching
anything**, because grep-ing them has repeatedly missed the rule that
mattered.

That instruction is correct and it is also the whole cost: an agent fixing a
label in a footer bar reads 118k tokens of context about Hyprland's Lua
dispatch, wallpaper blur regions, and the updater's checkout semantics. With
four agents in flight that is roughly half a million tokens spent before any
of them has read a line of code.

Where the mass actually is:

| Section | Lines | % | Commit citations |
|---|---:|---:|---:|
| Dynamic/data-driven QML gotchas | 2,910 | 51% | 113 |
| Design language | 1,184 | 21% | 42 |
| Layer-shell gotchas | 342 | 6% | 16 |
| Directory map | 308 | 5% | 8 |
| Hyprland integration | 222 | 4% | 5 |
| External binaries the shell drives | 171 | 3% | 10 |
| The Config system | 171 | 3% | 5 |
| State propagation is reactive | 139 | 2% | 8 |
| (nine smaller sections) | ~270 | 5% | — |

Two sections are 72% of the file. They are also the two with the highest
citation density, so they are not padding — they are the accumulated
"we learned this the hard way" record, and deleting is not on the table.

## Why a naive split breaks things

Anything that moves text out of `AGENT.md` has to answer all of these:

1. **61 files reference `AGENT.md`** — tests, lints, workflows,
   `CONTRIBUTING.md`, proposals. Many cite a section by name in an assertion
   message, which is how a failing test tells you which rule you broke.
2. **`tests/lint_doc_citations.py` hardcodes the doc set**
   (`DOCS = [AGENT.md, CONTRIBUTING.md, CLAUDE.md]`) *and* finds the repo
   root by walking up to the first directory containing `AGENT.md`. A split
   that adds files without teaching the lint about them silently stops
   checking their citations.
3. **Every commit citation must keep resolving.** Moving a paragraph is
   fine; rewriting one while moving it is how a citation quietly becomes
   wrong, and the lint only checks that the SHA exists, not that it says
   what the paragraph claims.
4. **The knowledge is cross-cutting, not per-subsystem.** "A `Loader`'s
   `active:` binding dies if anything assigns to it" applies to the bar, the
   settings host and the phone tab alike — it has already bitten three of
   them. Filing rules under the subsystem where they were discovered either
   duplicates them or strands them where the next victim will not look.
5. **The failure mode is asymmetric.** An agent that reads too much wastes
   tokens. An agent that misses a rule ships a defect, and several of these
   rules exist precisely because that happened. Any partition must fail
   toward "read it anyway".

## Candidate shapes

**A. By subsystem** (`docs/agent/bar.md`, `sidebar.md`, `settings.md`, …).
Matches the Directory map and an agent's mental model of "what am I
touching". Fails constraint 4: the two biggest sections are explicitly
cross-cutting.

**B. By rule type** — runtime model, QML/reactivity gotchas, layer-shell &
geometry, motion & design language, config & persistence, external
processes. This is what the existing headings already are, and the two
elephants split along a real seam (QML gotchas ≈ "how the engine betrays
you"; Design language ≈ "what the shell should look and move like"). An
agent doing a layout fix genuinely does not need the process-lifecycle
rules.

**C. Hybrid, recommended.** A thin always-read **core** — what the project
is, the runtime model, the hard rules whose violation breaks CI or the
shell, and an **index** — plus topic files under `docs/agent/` loaded on
demand, plus (where it earns its place) a short `AGENT.md` beside the code
it describes, since an agent editing `modules/imi/bar/` will read that
directory anyway.

The index is the load-bearing part: a table of *triggers*, not topics —
"touching a `Loader`, a `Repeater`, a `ListView`, or any binding you also
assign to → read `qml-reactivity.md`". An agent can only skip a file if it
can tell, before reading it, that it is irrelevant.

**D. Tooling** — keep one file, add a script that extracts relevant
sections. Rejected as the primary answer: it puts a guess between the agent
and the rules, and the guess fails silently.

## Open questions to settle before writing anything

- **What does the core owe?** Proposal: every rule that a lint or CI check
  enforces, stated once in full, because those are exactly the rules whose
  violation is expensive and whose text a test message points at. Depth,
  history and worked examples move out.
- **How is the split verified?** At minimum: extend `lint_doc_citations.py`
  to the new files; add a lint that every topic file is reachable from the
  index and that the core stays under a line budget; and check that no test
  or workflow references a section that has moved without its pointer being
  updated.
- **How do we know it worked?** Measure the before/after token cost of the
  brief an agent actually loads for three real past tasks (a footer label,
  a new service, a layer-shell bug) rather than the size of the files.
- **Does `CLAUDE.md` fold into the core, or stay the entry point that
  points at it?** It already exists and is in the lint's doc set.
- **Migration in one PR or several?** One move-only PR per topic file, with
  the text unchanged, is reviewable by diff; rewriting while moving is not.

## Sequencing

Not while other branches are open. Every agent's PR touches `AGENT.md`
(the docs-receipt workflow effectively requires it), so a partition landing
mid-flight conflicts with all of them. Do this when the tree is quiet, in
move-only steps, and update the agent briefs and `CONTRIBUTING.md`'s
"read both in full" instruction in the same PR that makes it untrue.
