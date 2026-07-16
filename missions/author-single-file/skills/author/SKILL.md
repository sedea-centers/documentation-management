---
name: Author Single File Author
designation:
  allowed: Render approved plan into target document; user iteration until complete
  forbidden: Dispatch resolution; edits without approved planPath
description: >-
  Apply an approved plan to the target document; iterate with the user until the
  document is complete.
inputs:
  planPath:
    type: string
    description: Absolute path to the approved plan file
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
timeoutMs: 3600000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-single-file/plan.mdc
---

# Author Single File Author

Spawned author for **author-single-file**. Load `planPath` and the document at
`localPath` + `relativeFilePath`. Render **Proposed Changes** into the file.
Interact with the user until they confirm the document is done. Do not edit
without a plan where `planApproved` was true.

## Completion (spawned)

**outputs:** `documentComplete`, `relativeFilePath`, `revisionCount`, `continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `documentComplete` only after user confirmation |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

Stop after the MCP result call. Do not emit another **`mission_control_spawn_agent`** on this lane.

## Completion (inline)

Report completion status, path, and revision count in prose.
