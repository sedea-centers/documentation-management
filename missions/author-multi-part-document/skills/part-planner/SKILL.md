---
name: Multi-Part Document Part Planner
designation:
  allowed: >-
    Plan one document part from the master plan; define part-plan shape in
    session; write approved part plan under dispatch plans/
  forbidden: >-
    Dispatch resolution; full-document one-pass authoring; spawning author or
    other children from this lane
description: >-
  Spawned part planner for author-multi-part-document. Draft and approve a plan
  for a single master-plan part; part-plan structure is defined during the
  planning session.
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
timeoutMs: 1800000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-multi-part-document/plan.mdc
---

# Multi-Part Document Part Planner

Spawned **part-planner** for **author-multi-part-document**. Plan **one** part
from the approved master plan. Do **not** author full document prose here.

## Inputs

- `partId`, `partTitle` — identity from the master plan ledger
- `masterPlanPath` and/or `masterPlanExcerpt` — binding overview for this part
- `localPath`, `relativeFilePath` — target document context
- `operationsDocsDirectory` — ops docs root (do not invent dispatch paths)

## Steps

1. Load master-plan context for `partId`. Confirm the part is incomplete or the
   user explicitly requested a replan.
2. Intake how this part should be structured for this session (sections,
   outcomes, sources). Part-plan shape is **session-defined**, not a fixed
   global template.
3. Draft the part plan under the dispatch bundle **`plans/`** directory.
4. USER_CHECKPOINT — approve part plan · revise · defer part · abort.
5. On approval, set `partPlanApproved: true` and complete.

**Forbidden:** planning every remaining part in one pass; editing the target
document body on this lane; calling `mission_control_propose_dispatch_resolution`.

## Completion (spawned)

**outputs:** `partId`, `partPlanPath`, `partPlanApproved`, `continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `partPlanApproved` only after user approval |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

Stop after the MCP result call. Do not emit another **`mission_control_spawn_agent`** on this lane.

## Completion (inline)

Report `partId`, part plan path, approval status, and `continuationStatus` in prose.
