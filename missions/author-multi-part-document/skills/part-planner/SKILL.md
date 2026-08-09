---
name: Multi-Part Document Part Planner
designation:
  allowed: >-
    Plan one document part from the master plan; define part-plan shape in
    session; resolve open questions/concerns via structured choice; write
    approved part plan under dispatch plans/; spawn author for this part; notify
    author of plan revisions
  forbidden: >-
    Dispatch resolution; full-document one-pass authoring; documenting open
    questions only in the plan file and expecting prose answers at approval;
    requiring Squad Leader to re-spawn author for plan revisions
description: >-
  Spawned part planner for author-multi-part-document. Draft and approve a plan
  for a single master-plan part; spawn the author child; push plan revisions
  directly to that author lane.
inputs:
  partId:
    type: string
    description: Stable part id from the approved master plan
    required: true
  partTitle:
    type: string
    description: Human title for this part
    required: true
  masterPlanPath:
    type: string
    description: Absolute path to the approved master plan artifact when available
    required: false
  masterPlanExcerpt:
    type: string
    description: Master-plan excerpt for this part when full path is unavailable
    required: false
  relativeFilePath:
    type: string
    description: Target document path relative to localPath
    required: true
  localPath:
    type: string
    description: Absolute local root for the documentation folder
    required: true
  operationsDocsDirectory:
    type: string
    description: Absolute ops docs write root from Mission Control
    required: true
  markupMode:
    type: string
    description: pending (track changes) or final (direct write) propagated from §3 intake; default final when omitted
    required: false
timeoutMs: 3600000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-multi-part-document/plan.mdc
---

# Multi-Part Document Part Planner

Spawned **part-planner** for **author-multi-part-document**. Plan **one** part
from the approved master plan, then **spawn author** for that part. Do **not**
author full document prose here.

## Inputs

- `partId`, `partTitle` — identity from the master plan ledger
- `masterPlanPath` and/or `masterPlanExcerpt` — binding overview for this part
- `localPath`, `relativeFilePath` — target document context
- `operationsDocsDirectory` — ops docs root (do not invent dispatch paths)
- optional **`markupMode`** (`pending` | `final`; default **`final`** when
  omitted or unrecognized)

## Steps

1. Load master-plan context for `partId`. Confirm the part is incomplete or the
   user explicitly requested a replan. Resolve **`markupMode`** from spawn
   **`inputs`** — **`final`** when omitted or unrecognized.
2. **Lane title refresh (binding — own slot):** Build **`title`** =
   **`P{nn} — {partTitle}`** per **`plan.mdc`** § *Part-planner lane title*
   (zero-pad `partId` to `{nn}`; truncate `{partTitle}` tail only if the full
   string exceeds 64 chars). When spawn chrome is generic or stale (for example
   `"Multi-Part Document Part Planner"` / truncated `"Part Planne…"`), call MCP
   **`mission_control_update_lane_display`** with that **`title`** and optional
   **`hoverDescription`** (`partId` + full `partTitle`, ≤512). **Skip** when the
   own-slot title already matches. **Forbidden:** leader-lane MCP to relabel this
   child slot (rule **9**).
3. Intake how this part should be structured for this session (sections,
   outcomes, sources). Part-plan shape is **session-defined**, not a fixed
   global template.
4. Draft the part plan under the dispatch bundle **`plans/`** directory. Include
   an **Unresolved Questions/Concerns** section (empty when none remain).
   - **Relevant Links (post-write):** After each Write/StrReplace that **creates
     or materially edits** the part plan, call MCP
     **`mission_control_update_relevant_documents`** with the absolute
     `partPlanPath` (`kind: plan`) on this lane — same turn preferred. **Skip**
     read-only loads and unchanged already-registered paths. See
     **`../README.md`** § *Relevant Links — post-write registration*.
5. **Guided open-question resolution (binding):** Enumerate every open question,
   concern, ambiguity, or incompleteness that blocks a clean part plan. For
   **each** item, ask via **structured choice** (`mission_control_present_structured_choice`
   / AskQuestion) — **one `askQuestion.questions` entry per open item** (same
   modal may batch multiple questions). Update the draft from selections.
   - **Forbidden:** listing open items only in the part plan (or recap) and
     expecting the user to answer them in free-form prose during plan
     review/approval.
   - Mirror **author-simple-document** planner: each unresolved question or
     unknown is asked via structured choice (one question per gate / per
     `questions[]` entry).
6. USER_CHECKPOINT — approve part plan · revise · defer part · abort.
   When open items remain after step 5, **co-present** per-item resolution picks
   **and** Approve / Revise / Defer / Abort on the **same** turn — **forbidden**
   to hide Approve until all items are cleared.
7. On approval, set `partPlanApproved: true`. Then emit
   **`mission_control_spawn_agent`** for **`skills/author/SKILL.md`** with
   `partPlanPath`, `partId`, `localPath`, `relativeFilePath`,
   `operationsDocsDirectory`, and resolved **`markupMode`**. Record the author
   child slug for revision notify.
   Set `continuationStatus: active`. Open **#external-wait** for the author
   result (do **not** emit a terminal planner result yet).
8. **Plan revisions after author spawn (binding):** When the part plan is revised
   while the author lane is active, push the revision to the **author** child:
   - Prefer **`mission_control_notify_child_lanes`** with
     `changeType: plan-revision`, `affectedPlanPaths: [<partPlanPath>]`, and
     `targetSlugs: [<authorSlug>]` when plan-change notification is enabled.
   - Otherwise re-handoff the updated `partPlanPath` on the author lane without
     Squad Leader re-spawn.
   - **Forbidden:** requiring Squad Leader to re-spawn author solely to deliver a
     plan revision.
9. On author **`mission_control_send_agent_result`** for this part (success,
   partial, deferred, or failure), merge author outputs (including SoT follow-up
   fields: `sotPresent`, `sotConsulted`, `sotFollowUpPath`, `sotFollowUpStatus`,
   `sotFollowUpCount`) into the planner result and complete this skill
   (`continuationStatus: terminal`).

**Forbidden:** planning every remaining part in one pass; editing the target
document body on this lane; calling `mission_control_propose_dispatch_resolution`;
prose-only open-question collection at the approval gate; emitting a **terminal**
planner result before author has finished (or the part is deferred/aborted
without author).

## Completion (spawned)

**outputs:** `partId`, `partPlanPath`, `partPlanApproved`, `unresolvedCount`,
`authorSpawned`, `authorSlug`, `partComplete` (when author reported),
`sotPresent`, `sotConsulted`, `sotFollowUpPath`, `sotFollowUpStatus`
(`none` | `appended` | `no-sot` | `skipped`), `sotFollowUpCount`,
`continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `partPlanApproved` only after user approval; `unresolvedCount` = remaining open items (0 when none); set `authorSpawned: true` and `authorSlug` after author spawn; forward author SoT follow-up fields when present; keep `continuationStatus: active` until author terminal (or defer/abort without author) |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) — including milestone updates after author spawn when useful |

After author spawn, **do** emit **`mission_control_spawn_agent`** for author on
this lane. Emit the **terminal** planner result only after step 9.

## Completion (inline)

Report `partId`, part plan path, approval status, `unresolvedCount`, author spawn
status, and `continuationStatus` in prose.
