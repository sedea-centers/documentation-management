---
name: Multi-Part Document Gap Closer
designation:
  allowed: >-
    Apply approved gap-closer actions to the target document using the gap
    report; iterate until closed or remaining gaps are recorded
  forbidden: >-
    Dispatch resolution; inventing gaps not in the report; editing without a
    gap report path from gap-analyzer
description: >-
  Spawned gap closer for author-multi-part-document. Close contradictions or
  misinterpretations listed in an approved gap report; leave unresolved items
  explicit for the parent ledger.
inputs:
  gapReportPath:
    type: string
    description: Absolute path to the gap-analyzer report
    required: true
  relativeFilePath:
    type: string
    description: File path relative to localPath
    required: true
  localPath:
    type: string
    description: Absolute local root for the documentation folder
    required: true
  operationsDocsDirectory:
    type: string
    description: Absolute ops docs write root from Mission Control
    required: true
  closerActions:
    type: array
    description: Optional subset of proposed closer actions to apply
    required: false
timeoutMs: 3600000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-multi-part-document/plan.mdc
  - .sedea/centers/documentation-management/rules/20_source-of-truth.mdc
---

# Multi-Part Document Gap Closer

Spawned **gap-closer** for **author-multi-part-document**. Load `gapReportPath`
and close listed gaps in the target document with user confirmation.

## Inputs

- `gapReportPath` — binding gap report from **gap-analyzer**
- optional `closerActions` — subset when the parent narrowed scope
- `localPath`, `relativeFilePath`, `operationsDocsDirectory`

## Steps

1. Load the gap report. Do not invent findings outside it.
2. USER_CHECKPOINT when multiple closer strategies exist — pick path per gap or
   batch-approve proposed actions.
3. Apply edits to `localPath` + `relativeFilePath`. Consult
   **`<localPath>/source-of-truth/`** when present; never write under it.
4. Confirm with the user which gaps are closed. Record `remainingGaps` for any
   deferred or disputed items.

**Forbidden:** dispatch resolution; expanding scope into new part authoring
beyond gap closure.

## Completion (spawned)

**outputs:** `gapsClosed`, `remainingGaps`, `relativeFilePath`,
`continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

Stop after the MCP result call. Do not emit another **`mission_control_spawn_agent`** on this lane.

## Completion (inline)

Report closed vs remaining gaps and document path in prose.
