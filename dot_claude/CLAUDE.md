## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.

## Hand-drawn diagrams have a mermaid twin

A hand-authored SVG embedded in README (or any doc) has no layout engine behind it:
every coordinate is a decision, so a `git diff` of one is a wall of numbers where a
deleted edge and a nudged label look identical. Every such drawing therefore has a
sibling `.mmd` holding the same graph with **no geometry** — nodes, edges, labels only.

- The `.mmd` is the semantic source: it is what a reviewer reads and the only part a
  diff can show. If drawing and `.mmd` disagree, the `.mmd` is believed.
- Change both in the **same commit**, never one without the other. The surrounding
  prose stays the source of truth for the facts; the drawing is embedded, not inlined
  as a mermaid block.
- Reading order when picking a drawing up cold: prose, then `.mmd`, then the SVG's
  `metadata id="edit-guide"`, then the drawing itself.
- Never run svgo or any SVG optimizer on it — it strips the edit guide and rewrites paths.

**Enforce it with a script, not a comment.** "Update both together" inside a file
nobody opens is not a guarantee. Keep a checker that fails on:
  - forward — a node or edge label declared in the `.mmd` that is not drawn in the SVG
  - reverse — a node drawn in the SVG that is not declared in the `.mmd`
  - embed — the doc no longer embeds the SVG
  - guide — the edit-guide metadata went missing

Strip `<metadata>`, `<title>`, `<desc>` and comments before the forward check, or
prose that merely names a component satisfies it.
Wire the checker into both the test suite and the merge gate, so the guarantee does
not depend on remembering a separate command.

**It checks meaning, not geometry.** Nothing automated notices a label sitting on a
box. Before claiming a diagram change is done, render it and look:
`rsvg-convert -w <width> path.svg -o /tmp/d.png`, and parse the `.mmd` with `mmdc`.

**Third-party components carry their official logo; ours carry none.** The mark is
what tells a reader at a glance which boxes we did not write, so the absence is as
meaningful as the presence — never decorate an in-house service.

- Marks go in `<defs>` as `<symbol id="i-<slug>" viewBox="0 0 24 24">` and are placed
  by `<use>`, one size for all of them, inset a fixed distance from the node's left
  edge, filled with that node's own text colour so they read as part of the box.
- Source the paths from Simple Icons (CC0 files; the marks themselves remain their
  owners' trademarks, used nominatively):
  `curl -s https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/<slug>.svg`
- No official mark: either borrow the parent product's mark or hand-draw a generic
  glyph — and write down which, and why, in the edit guide. When a mark would assert
  something false (naming a component's upstream vendor rather than the component),
  leave it off deliberately and record that too.
- A glyph must not touch the node's caption. Captions are centred, so re-render and
  look after adding one, and shorten the caption rather than move the glyph.

## New work goes in a worktree, not a branch

Start any new piece of work with `wt switch -c <branch>` (worktrunk), never
`git checkout -b` in the main checkout. Base defaults to the default branch;
`-b <base>` overrides. `wt merge` lands it, `wt remove` cleans up.

- The worktree lands as a sibling of the main checkout, one branch per worktree.
- A repo's `.config/wt.toml` post-start hook carries the git-ignored files a fresh
  checkout needs (`.env`, …) into the new worktree — one made by hand comes
  up without them. A non-interactive shell needs `--yes` to approve that hook.
- Pair that hook with `--require-include` and a `.worktreeinclude` allow-list.
  Bare `wt step copy-ignored` copies **every** gitignored path: in leobroker that
  silently put a ~10 GB backup tree into each of three worktrees. A deny-list is
  the wrong shape — it needs extending every time a new ignored directory appears,
  and forgetting costs gigabytes. `--require-include` also fails closed if the
  allow-list is ever deleted.
- A copied `.venv` may still point its console scripts at the original checkout's
  interpreter; rebuild it in the worktree rather than trusting it.
- Merges stay linear, per the rule below.

## Keep git history linear

I dislike merge commits and the tangled "guitar-hero" graph they create. History
stays linear — every branch lands as a fast-forward or a squash, never as a bubble.

- Pull with `--ff-only`, never a merge-pull. If it will not fast-forward, rebase —
  do not merge.
- To advance a branch ref when the working tree is dirty (a rebase-pull refuses
  there), use `git merge --ff-only origin/<branch>`: it fast-forwards, writes no
  commit, and leaves unrelated working changes intact.
- Merge requests / pull requests: fast-forward or squash, not a merge commit. Reach
  for `--squash` when a branch has messy intermediate commits.
- Never run a plain `git pull` on a shared branch if it could synthesize a merge commit.
- My main checkouts often carry permanently unstaged IDE files and local drafts, so a
  plain pull fails on the dirty tree there. `git -C <checkout> merge --ff-only
  origin/<default-branch>` is the safe way to update them.
