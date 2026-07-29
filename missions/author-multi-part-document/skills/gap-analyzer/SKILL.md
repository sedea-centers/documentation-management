---
name: Multi-Part Document Gap Analyzer
designation:
  allowed: >-
    Compare authored parts for contradictions or misinterpretations; write a
    gap report; spawn gap-closer when gaps are found; aggregate closer outputs
    into one terminal result to Squad Leader
  forbidden: >-
    Dispatch resolution; silently editing the document to close gaps; emitting
    terminal result before gap-closer finishes when closer was spawned; requiring
    Squad Leader to spawn gap-closer on the happy path
description: >-
  Spawned gap analyzer for author-multi-part-document. Detect contradictions or
  misinterpretations across authored parts relative to the master plan; report
  gaps; spawn gap-closer on this lane when gaps are found.
inputs:
  authoredPartRefs:
    type: array
    description: Paths or identifiers for authored parts to compare
    required: true
  masterPlanPath:
    type: string
    description: Absolute path to the approved master plan when available
    required: false
  focusHints:
    type: string
    description: Optional user focus for the analysis
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
timeoutMs: 3600000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-multi-part-document/plan.mdc
---

# Multi-Part Document Gap Analyzer

Spawned **gap-analyzer** for **author-multi-part-document**. Compare newly
authored parts with previously authored parts (and the master plan) for
contradictions or misinterpretations. Produce a gap report; when gaps are found,
**spawn gap-closer** on this lane (nested spawn — mirror part-planner → author).

## Inputs

- `authoredPartRefs` — parts in scope for comparison
- `masterPlanPath`, optional `focusHints`
- `localPath`, `relativeFilePath`, `operationsDocsDirectory`

## Steps

1. Load the master plan (when provided) and the authored part content in scope.
2. Analyze for contradictions, duplicated conflicting claims, and
   misinterpretations of the master plan or earlier parts.
3. Write a gap report under the dispatch bundle **`plans/`** (or ops docs when
   the parent instructs) with concrete findings and optional proposed closer
   actions.
   - **Relevant Links (post-write):** After the gap report write, call MCP
     **`mission_control_update_relevant_documents`** with the absolute
     `gapReportPath` (`kind: plan`) on this lane — same turn preferred. See
     **`../README.md`** § *Relevant Links — post-write registration*.
4. Set `gapsFound: true | false`.
5. **If `gapsFound: false`:** emit terminal result to Squad Leader
   (`continuationStatus: terminal`).
6. **If `gapsFound: true`:** USER_CHECKPOINT — spawn gap-closer with full report
   · spawn subset of proposed closer actions · skip closer (report only).
7. **On closer spawn pick:** emit **`mission_control_spawn_agent`** for
   **`skills/gap-closer/SKILL.md`** with `gapReportPath`, `localPath`,
   `relativeFilePath`, `operationsDocsDirectory`, and optional `closerActions`.
   Record the gap-closer child slug. Set `continuationStatus: active`. Open
   **#external-wait** for the closer result (do **not** emit a terminal analyzer
   result yet).
8. **On gap-closer terminal:** merge closer outputs (`gapsClosed`,
   `remainingGaps`) and emit **one** terminal
   **`mission_control_send_agent_result`** to Squad Leader.

**Forbidden:** editing the target document to “fix” gaps here; dispatch
resolution; emitting a **terminal** analyzer result before gap-closer has
finished when closer was spawned; requiring Squad Leader to spawn gap-closer on
the happy path.

## Completion (spawned)

**outputs:** `gapReportPath`, `gapsFound`, `proposedCloserActions`,
`gapCloserSpawned`, `gapCloserSlug`, `gapsClosed`, `remainingGaps`,
`continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; set `gapCloserSpawned: true` and `gapCloserSlug` after closer spawn; keep `continuationStatus: active` until closer terminal (or skip/defer without closer) |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

After closer spawn, **do** emit **`mission_control_spawn_agent`** for
gap-closer on this lane. Emit the **terminal** analyzer result only after step 8
(or step 5 when no closer).

### Host protocol line

Nested spawn: gap-analyzer owns **`mission_control_spawn_agent`** for
gap-closer and waits for the child terminal before reporting to Squad Leader.
gap-closer terminal delivers to **this** lane, not Squad Leader.

## Completion (inline)

Report gap report path, `gapsFound`, closer spawn status, and closed vs
remaining gaps in prose.
