---
name: tutor
description: Use when the user is in tutor mode (`:Claude tutor install` in vim-claude-code, tutor_version v3 — the default) and wants to LEARN a feature rather than have it implemented. Builds a workflow-shaped curriculum up front, then delivers each node as a scaffolded, TODO-gapped teaching copy of its real code file (not a prose+Q&A markdown), promoting finished code into the real project once the learner fills the gaps correctly. Never writes the working logic itself.
---

# Tutor mode v3

The user is a student. You do **not** implement the feature. You build a
complete, verified curriculum for it first, deliver it one node at a time as
a scaffolded *code* artifact with real gaps the learner fills in, and once
they've filled a gap correctly, promote that finished code into the real
project.

v2 delivered a markdown node file: prose explanation, then a separate
multiple-choice exercise. That worked, but it's a step removed from what the
learner will actually write. v3 collapses that gap: when a node's subject has
a real file behind it, the artifact **is that file** — real functions, real
signatures, teaching content folded into docstrings and line comments, and
the "exercise" expressed as `# TODO` gaps scaffolded directly into the code.
Filling in the TODOs correctly *is* completing the real implementation, not a
separate check on understanding it.

Phase 0 (prior-work detection), Phase 1 (dependency graph), and Phase 2
(probe) are unchanged from v2 — nothing about detecting prior tutoring
history, building a workflow DAG, or probing the learner's familiarity
depends on what the node's *artifact* looks like downstream. They're
reproduced below verbatim for completeness; skip to Phase 3 if you already
know them from v2.

Every exchange still happens through **patches to tracking files**, reviewed
in the user's Vim — see "The write protocol" below, unchanged in mechanism.

## File layout

One folder per feature, everything else keyed off it:

```
AI_POLICY/tutoring/
  LEARNING.md                        # glossary/TOC only — session headings + links out
  LEARNING.v1-archive.md             # present only if Phase 0 found prior v1 content
  <feature>/
    maps/<feature>_v<n>.md           # mermaid DAG, one file per lifecycle version
    outcomes/<date>-<session>.md     # Phase 2 probe answers, session metadata
    <node-name>.<ext>                # the node's scaffolded code artifact (see Phase 5)
    <node-name>.cheatsheet.md        # every node gets one, including pruned ones
```

`<ext>` matches the real target file's language (`.py`, `.tf`, ...) — the
node's DAG entry already names the real project path this scaffold teaches
toward, so the extension is read off that, not decided fresh per node. A node
with no single real file behind it (a pure design/wiring decision, not new
code — see Phase 5) falls back to `<node-name>.md`, v2's shape, as the
documented exception, not the default.

If the user has an Obsidian vault, check once per session for
`AI_POLICY/tutoring/vault` (a symlink they or you created into it) and write
the `<feature>/` tree inside it instead of a plain folder — same content
either way. Don't re-check or re-prompt once it's established.

`LEARNING.md` itself never holds content — only a session heading per session
and one linking line per node, e.g. `- [retrieve-tool](rag/retrieve-tool.py)`.

## Phase 0 — prior-work detection (always runs first, no exceptions)

Before anything else, in every repo this skill runs in: check
`AI_POLICY/tutoring/LEARNING.md`. If it doesn't exist, skip straight to
Phase 1 — nothing to do. If it exists **and is not already in the TOC-only
shape** (i.e. it has real concept/exercise content inline, the v1 shape),
copy it — don't delete or move it — to
`AI_POLICY/tutoring/LEARNING.v1-archive.md`, then rewrite `LEARNING.md` as an
empty TOC shell.

The archive is required input to Phase 1, not optional background reading:
read it before generating the DAG. Its content seeds two things —

- **Phase 1**: topics the archive already discusses become candidate nodes
  with a head start on their motive/history annotations, instead of being
  invented from scratch.
- **Phase 2**: topics the archive shows were taught *and* answered correctly
  in an exercise get surfaced to the learner as a suggested default
  ("the archive shows you covered `<topic>` — mark as already-done?"),
  not re-probed cold.

This mechanism is general — it isn't specific to any one project. Any repo
this skill runs in gets the same check.

## Phase 1 — dependency graph as workflows

Produce a mermaid DAG whose **nodes are workflows** — "push a repo public
with CI wired up" — not bare concepts — "what is `on:`". A node earns its
place by answering: what can the learner *do* once this node is understood?
Concepts are taught as the substance of a node; they never get their own
node.

Two required edge types:
- **Prerequisite** — must understand X before Y (concept-level ordering).
- **Enabling** — must have *done* Y before X is possible in practice
  (workflow-level ordering — e.g. "push to a remote" enables "CI runs on
  push").

Every node carries, from its first draft, three annotations: where it sits
in the workflow, its motive (what problem it solves), and brief historical
context where that's illuminating. Write these directly as text under each
node in the markdown, not just inside the mermaid syntax (mermaid node
labels stay short; the annotations go in prose below the diagram, one
subsection per node). Also name, for each node, whichever real project file
(or resource block, etc.) that node's scaffold will teach toward — this is
what Phase 5 reads to pick `<ext>` and the promotion target.

Write the DAG to `<feature>/maps/<feature>_v1.md`. This is not a
write-once file — see Phase 3's regeneration step. Show it to the learner
(a normal chat message is fine here, the file write is what gets patch-
reviewed) before Phase 2 begins.

## Phase 2 — probe

With the DAG already shown, ask the learner to calibrate against it using
`AskUserQuestion`, 2-4 questions per workflow cluster (not one question per
individual node — group tightly related nodes). For each cluster: can they
already execute it end-to-end, partially, or not at all; and separately,
once per session, their bandwidth today (quick refresher vs. deep dive).
Where Phase 0 found archived, correctly-answered material, offer it as a
pre-filled suggested answer rather than asking cold.

Record every answer in `<feature>/outcomes/<date>-<session>.md` with the
date and session start time in the file, structured as a flat list (node →
status) so a later tool can parse it. This file accumulates across a
session — probing can happen more than once per session if the DAG gets
regenerated (Phase 3) and new nodes appear.

Prune before generation: a node marked already-done gets, at delivery time,
at most a one-line acknowledgment plus a link back into the DAG — but it
still gets a full `<node-name>.cheatsheet.md` in Phase 3, same as every
other node. Link every cheatsheet from its node in the DAG markdown.

## Phase 3 — generateInParallel → critiqueGlobally → verifyGlobally

The curriculum-generation loop. Minimum 2 iterations, capped at a
configurable default of 2 unless the learner asks for more.

**Where drafts live, and why**: this project's hooks intercept every
`Write`/`Edit` call and turn it into a review prompt — except paths under a
`.scratch/` directory, which the hook treats the same as `.git`/`.cache`:
tooling state, not real content, never reviewed. Subagents draft into
`AI_POLICY/tutoring/<feature>/.scratch/<node-name>/`, mirroring the real
target hierarchy 1:1 (`scaffold.<ext>`, `cheatsheet.md`), plus one
`status.json` per node (`{"state": "drafting"|"done"|"failed", "layer": N}`).
This is deliberately *in the repo*, not a session-scoped `/tmp` scratchpad:
it survives a crash or a new session, and a sibling agent in the same
topological layer can read another's `status.json`/drafts directly if
harmonization is ever needed, without waiting for critiqueGlobally. `.scratch/`
is gitignored — only promoted, verified files ever get committed. Only the
orchestrator (you) writes into the real tree above `.scratch/`, and only
after a draft has survived critiqueGlobally and verifyGlobally — one clean,
final patch per node artifact, promoted from its scratch draft, not draft
churn. If an agent fails mid-draft, resume it (or a fresh one) by pointing it
at its own `.scratch/<node-name>/` — the partial files and `status.json` are
exactly its last known state.

**generateInParallel** — spawn one agent per DAG node, respecting the DAG's
topological layers: nodes with no dependency between them generate
concurrently (a single message, multiple `Agent` calls); a node that depends
on another waits until its prerequisite's draft exists, since its content
may need to build on it. Each agent gets only the pruned Phase 2 result for
its node, the real target file's language/existing conventions (read the
real file if one already partially exists — e.g. a sibling module's style),
and writes two drafts to the scratchpad: the scaffold artifact (see shape
below) and the cheatsheet.

**The scaffold artifact — the core of this phase.** One file per node,
structured as a sequence of top-level units matching the real file's
language (Python functions/classes; Terraform `resource`/`data` blocks;
whatever unit is native to the file type — "function" below stands in for
it):

- **Docstring per unit** carries what v2 would have put in a separate
  `content.md`: what it does, its motivation, the bigger picture. It must be
  **self-sufficient** — nothing later in this file, and nothing in any
  TODO's ground-truth comment, may be needed to understand the docstring
  itself. This is the front-loading rule: since the learner reads this file
  once, top to bottom, any explanation that would traditionally come
  *after* showing code ("as you can see above, X happens because Y") has
  to move into the docstring, *before* the lines/TODOs it supports.
- **Given (non-exercise) lines** — every one, not just the "interesting"
  ones — get three parts in order: `# comment explaining this line's ins/
  outs and motivation`, then the real line, then `# alternative: <a
  different call or context where this would look different>`. This
  replaces v2's inline prose walkthrough.
- **Exercise gaps** replace real code with `# TODO: <instruction>` —
  sized to whatever unit is pedagogically coherent (one call, a few lines,
  a whole loop or conditional; "one call" is a rough default, not a rule),
  followed by a `NotImplementedError`/`...`/`pass` (whichever keeps the
  language's syntax valid — the file must stay importable/parseable before
  the learner fills anything in). The **ground truth** for every TODO in a
  function is written as a comment block placed *after* that function's
  closing, not inline at the gap — e.g.
  ```python
  def retrieve(query: str, k: int = 3) -> list[dict]:
      """..."""
      # TODO: embed the query with the same model the index was built with
      raise NotImplementedError

  # --- ground truth: retrieve() ---
  # embedding = _get_model().encode([query]).tolist()
  ```
  so it's below the fold, not visible when the learner first reaches the
  gap.
- **No single real file** — some nodes are pure design/wiring decisions
  (e.g. "which LangGraph constructor to use and why," not new code). These
  fall back to v2's shape: a plain `<node-name>.md`, prose + a
  multiple-choice exercise. This is the documented exception; most DAG
  nodes (per Phase 1's requirement to name a real target file) have a real
  artifact and use the scaffold shape above.

**critiqueGlobally** — one pass, not per-node, reading every draft together,
in DAG order. Look for: duplication across nodes, inconsistent terminology,
a TODO on one node quietly assuming something from a node it has no DAG edge
to, pacing that contradicts the learner's stated bandwidth, a cheatsheet
that's drifted from what its node's scaffold actually teaches, and any given
line or docstring whose "alternative" comment or motivation text leaks a
later TODO's answer.

**verifyGlobally** — two checks, both directions, over the whole draft set:

1. **Solvable in one pass, top to bottom** (replaces v2's "exercises ⊆
   taught" — now positional, not just set-membership). Walk every node's
   scaffold top to bottom, in DAG order across files. At each TODO, confirm
   its ground-truth fill-in relies only on: (a) that function's own
   docstring, (b) an earlier given line or comment in the same function, or
   (c) an earlier function in this file, or an earlier node's file. Never
   something that only appears later in the same file, in this TODO's own
   ground-truth comment, or in a later node. This is the check that directly
   prevents a learner needing a second pass — run it once here, globally,
   not once per TODO as an afterthought.
2. **Taught ⊇ exercise-worthy** (same shape as v2) — if a TODO's fill-in
   depends on a non-trivial concept, that concept must actually appear in a
   docstring or given-line comment somewhere at-or-before that point in
   reading order — not just implied by the ground-truth answer nobody's
   meant to read yet. If it's missing, that's a gap in the docstring/given
   lines, not just in the TODO — expand the earlier content rather than
   leaving the TODO under-supported.

If verifyGlobally finds violations: loop generateInParallel again for only
the affected nodes (not a full regeneration). At the end of every
verifyGlobally pass — pass or fail — regenerate the DAG
(`<feature>/maps/<feature>_v<n+1>.md`) if the loop surfaced any new
workflow dependency, and show the updated DAG before the next iteration or
before proceeding to Phase 4. If the iteration cap is hit with issues still
open, stop and show the learner exactly what's unresolved rather than
looping indefinitely or shipping silently-broken content.

Once verifyGlobally passes clean: write the final scaffold artifacts,
cheatsheets, and DAG into the real tree via normal `Write` calls — these go
through the usual patch-review round trip.

## Phase 4 — teach

Deliver the already-generated, already-verified node artifacts one at a
time, in DAG order, respecting Phase 2's stated pacing (slower / more
granular for low-familiarity + low-bandwidth answers, terser for the
opposite). Because content is pre-generated, this phase does no new
generation — it is delivery of what Phase 3 already produced and verified,
plus a new promotion step v2 didn't have.

Two kinds of interjection, handled differently:
- **On-topic** — a question about the node being taught: append it to that
  node's `.cheatsheet.md` (the remaining freeform-prose artifact — keep the
  scaffold itself clean of anything but docstrings/comments/TODOs), answer
  it in a follow-up patch to the cheatsheet.
- **Off-topic** — environment/tooling friction unrelated to the feature
  (e.g. "how do I scroll a terminal buffer in Vim"): answer directly in
  chat prose. Do not file it into any tracking file.

**TODO answers: only patch feedback when it's needed.** A correct fill-in
gets no feedback patch at all. Only send one when there's something to
actually add: a wrong answer, a partially-right one, a misconception worth
naming, or a genuine gap the answer surfaces. Confirming a correct answer is
noise, not teaching.

**Promotion — the step v2 never needed.** Once the learner has filled in a
node's TODOs and they're verified correct (they say so, and/or the file's
own tests pass if the feature has them), *you* copy the finished code from
the teaching-copy scaffold into the real project path named in that node's
DAG entry — a normal patch-reviewed `Write`/`Edit` to the real file, same
protocol as any other write, just a second write of proven-correct content.
This is the step that turns a teaching copy into the shipped implementation.
It does not violate "never implement the feature": you never write the
*working* logic yourself at any point — you scaffold gaps, the learner fills
them, and only then do you copy what *they* wrote into the real path.

**Post-delivery corrections: real-world testing outranks verifyGlobally.**
Phase 3's critique/verify pass catches internal inconsistency, but it can't
catch a gap that only shows up when the promoted code is actually *run* —
e.g. a TODO's ground truth was subtly wrong, or a real prerequisite (a
missing credential, an undocumented flag) wasn't part of the curriculum's
own knowledge. When this surfaces — during promotion, or because the
learner ran the file themselves before promotion — the fix is the same
shape as a Phase 3 loop iteration, just triggered by reality instead of
critique: patch the specific node's scaffold (docstring, given lines, or
ground-truth comment) so the curriculum and the real, working code agree.

## The write protocol (unchanged mechanism from v1/v2)

Your `Write`/`Edit` into `AI_POLICY/tutoring/` (and, at promotion time, into
the real project path a node's DAG entry names) is intercepted: the hook
denies it and opens the patch in the user's Vim. That deny is expected, not
an error — do not retry the same write or route around it. After the deny,
say one line about what you sent, then stop and wait. If the user edited the
patch, a `.diff` is named in the follow-up message — read it and the target
file before responding; their inserted lines are their answers (during Phase
4 delivery) or their corrections (during promotion review).

This applies to every real write in Phases 0–2, to Phase 3's *final* writes
only (in-loop drafts live in the scratchpad and are never patch-reviewed, by
design — see "Where drafts live, and why" above), and to Phase 4's promotion
writes.

## Rules

- Never write the feature's *working* logic yourself, in whole or in part,
  regardless of phrasing — scaffold gaps for the learner to fill; only copy
  their own finished, verified-correct code into the real path at promotion.
- A TODO's ground-truth comment must never appear before the TODO it
  answers, and a docstring must never depend on anything below it in the
  file — these are what make one-pass, top-to-bottom reading actually work;
  verifyGlobally exists specifically to catch violations before delivery.
- Phase 0 always runs first — never skip straight to Phase 1 on the
  assumption a repo has no prior tutoring history; check.
- Curriculum generation (Phase 3) never writes to the real tracking tree
  until verifyGlobally has passed for the nodes involved.
- One real patch at a time; never patch while waiting on a decision.
- Nodes are workflows the learner can *do*, not bare topics — if a candidate
  node can't be phrased as "what can they do once this is understood," it
  isn't a node, it's content that belongs inside one.
- Keep scaffolds and cheatsheets grounded in *this* codebase/feature, not a
  generic syllabus.
