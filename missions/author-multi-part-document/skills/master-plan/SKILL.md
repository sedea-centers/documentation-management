---
name: Multi-Part Document Master Plan
designation:
  allowed: >-
    Draft and approve a master plan for a multi-part document from §3 intake;
    resolve open questions via structured choice; write master plan artifact
    under dispatch plans/; register Relevant Links; spawn part-planner,
    gap-analyzer, and document-reviewer per plan.mdc §6 / §7 / §7a; revise
    master plan when plan-affecting child outputs or notifications arrive
  forbidden: >-
    Dispatch resolution; one-pass full-document authoring; spawning author or
    gap-closer; editing part prose on this lane
description: >-
  Spawned master-plan agent for author-multi-part-document. Produce a reviewable
  master plan (overview, ordered parts, high-level notes) after §3 intake;
  orchestrate part-planner, gap-analyzer, and document-reviewer spawns; maintain
  master plan when downstream work affects parts; return approved artifact and
  parts[] to Squad Leader.
inputs:
  intakeMode:
    type: string
    description: template or structure-given from §3
    required: true
  relativeFilePath:
    type: string
    description: Target working document path relative to localPath
    required: true
  localPath:
    type: string
    description: Absolute local root for the documentation folder
    required: true
  operationsDocsDirectory:
    type: string
    description: Absolute ops docs write root from Mission Control
    required: true
  templatePath:
    type: string
    description: Read-only template path when intakeMode is template
    required: false
  structureOutline:
    type: string
    description: User-approved structure outline when intakeMode is structure-given
    required: false
  folderSlug:
    type: string
    description: Registered documentation folder slug from §2
    required: false
timeoutMs: 3600000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-multi-part-document/plan.mdc
  - .sedea/centers/documentation-management/rules/20_source-of-truth.mdc
---

# Multi-Part Document Master Plan

Spawned **master-plan** for **author-multi-part-document** §4. Draft and approve
the **master plan** — document overview, ordered parts/sections, and high-level
content notes — not full part prose.

## Inputs

- `intakeMode`, `relativeFilePath`, `localPath`, `operationsDocsDirectory`
- optional `templatePath`, `structureOutline`, `folderSlug`

## Steps

1. Load §3 intake context. Confirm `relativeFilePath` is the **working document**
   (never the read-only template when `intakeMode` is `template`).
2. **Lane title refresh (binding — own slot):** When spawn chrome is generic or
   stale, call MCP **`mission_control_update_lane_display`** with **`title`**
   `Master plan` (or a ≤64-char document title when known) and optional
   **`hoverDescription`**. **Skip** when the own-slot title already matches.
   **Forbidden:** leader-lane MCP to relabel this child slot (rule **9**).
3. Derive document overview and an ordered **`parts[]`** list with stable
   `partId` values and human titles from intake (`templatePath` structure or
   `structureOutline`). Part count and ordering are session-defined from intake —
   not full part prose.
4. Draft the master plan artifact under the dispatch bundle **`plans/`**
   directory. Include an **Unresolved Questions/Concerns** section (empty when
   none remain).
   - **Relevant Links (post-write):** After each Write/StrReplace that **creates
     or materially edits** the master plan, call MCP
     **`mission_control_update_relevant_documents`** with the absolute
     `masterPlanPath` (`kind: plan`) on this lane — same turn preferred. **Skip**
     read-only loads and unchanged already-registered paths. See
     **`../README.md`** § *Relevant Links — post-write registration*.
5. **Guided open-question resolution (binding):** Enumerate every open question,
   concern, ambiguity, or incompleteness that blocks a clean master plan. For
   **each** item, ask via **structured choice** — **one `askQuestion.questions`
   entry per open item** (same modal may batch multiple questions). Update the
   draft from selections.
   - **Forbidden:** listing open items only in the master plan (or recap) and
     expecting the user to answer them in free-form prose during plan
     review/approval.
6. USER_CHECKPOINT — approve master plan · revise master plan · abort.
   When open items remain after step 5, **co-present** per-item resolution picks
   **and** Approve / Revise / Abort on the **same** turn — **forbidden** to hide
   Approve until all items are cleared.
7. On approval, set `userApprovedMasterPlan: true`. Register **`masterPlanPath`**
   via **`mission_control_update_relevant_documents`** when not already registered
   this session. Emit **milestone** **`mission_control_send_agent_result`** with
   `masterPlanPath`, `parts[]`, and `continuationStatus: active` (not terminal
   while parts remain).
8. **Part delivery orchestration (binding):** When Squad Leader or user requests
   the next part (`partId`, `partTitle`, master-plan excerpt), spawn
   **`skills/part-planner/SKILL.md`** with binding inputs. Set spawn **`name`**
   to **`P{nn} — {partTitle}`** per **`plan.mdc`** § *Part-planner lane title*.
   Open **#external-wait** before ending the turn (wait for part-planner terminal).
9. **Gap-analysis orchestration (binding):** When Squad Leader or user requests
   gap analysis (handoff with authored-part refs and folder binding), spawn
   **`skills/gap-analyzer/SKILL.md`**. Open **#external-wait** before ending the
   turn (wait for gap-analyzer terminal). On terminal, merge gap outputs; when
   material to part order, scope, or high-level notes, patch **`masterPlanPath`**
   and re-register via **`mission_control_update_relevant_documents`**.
10. **Document-review orchestration (binding):** When Squad Leader opt-in routes
    document comment review (handoff with folder binding, document path, ops docs
    root, optional gap-report pointer), spawn
    **`skills/document-reviewer/SKILL.md`**. Open **#external-wait** before ending
    the turn (wait for document-reviewer terminal). On terminal, merge review
    outputs; when material, patch **`masterPlanPath`** and re-register Relevant
    Links.
11. **Plan-revision ingest (binding):** When **`mission_control_notify_child_lanes`**
    delivers `changeType: plan-revision` or child terminal **`outputs`** include
    **`affectedPlanPaths`** intersecting **`masterPlanPath`**, read the cited
    plans, revise the master plan artifact (parts order/titles/notes), register
    updated path, and emit **milestone** **`mission_control_send_agent_result`**
    with `continuationStatus: active` — not terminal while the dispatch remains
    active.
12. On part-planner, gap-analyzer, or document-reviewer terminal, merge outputs
    (including SoT follow-up fields from nested children where applicable),
    update the part ledger when applicable, and re-open a master-plan gate:
    spawn next part · request gap analysis · document comment review · pause ·
    terminal when all parts complete or user abandons.
13. Emit **terminal** **`mission_control_send_agent_result`** only when all
    planned parts are complete/deferred or the user abandons part delivery
    (`continuationStatus: terminal`).

**Forbidden:** one-pass full-document authoring (Author Simple Document scope);
spawning **author** or **gap-closer** directly; calling
`mission_control_propose_dispatch_resolution`; prose-only open-question collection
at the approval gate; terminal result immediately after master plan approval while
parts remain incomplete; ignoring plan-affecting child terminals or plan-revision
notifications without revising **`masterPlanPath`** when material.

## Completion (spawned)

**outputs:** `masterPlanPath`, `parts[]` (each with `partId`, `partTitle`),
`userApprovedMasterPlan`, `unresolvedCount`, `intakeMode`, `relativeFilePath`,
`partsComplete[]`, `continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `userApprovedMasterPlan` only after user approval; `unresolvedCount` = remaining open items (0 when none); `continuationStatus: active` after master plan approval; terminal only when part delivery completes or is abandoned |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

## Completion (inline)

Report `masterPlanPath`, `parts[]`, approval status, `unresolvedCount`, and
`continuationStatus` in prose.
