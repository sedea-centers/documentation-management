---
name: Author Simple Document Author
designation:
  allowed: >-
    Render approved plan into target document; consult folder source-of-truth
    when present; user iteration until complete
  forbidden: >-
    Dispatch resolution; edits without approved planPath; writes under
    source-of-truth/
description: >-
  Apply an approved plan to the target document using the folder source of truth
  when present; iterate with the user until the document is complete. Parent
  mission §6a owns post-author deviation reporting — this skill does not write
  SoT or open refresh source of truth.
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
  - .sedea/centers/documentation-management/missions/author-simple-document/plan.mdc
  - .sedea/centers/documentation-management/rules/20_source-of-truth.mdc
---

# Author Simple Document Author

Spawned author for **author-simple-document**. Load `planPath` and the document at
`localPath` + `relativeFilePath`. Render **Proposed Changes** into the file.
Interact with the user until they confirm the document is done. Do not edit
without a plan where `planApproved` was true.

## Source of truth (binding)

1. Check for **`<localPath>/source-of-truth/`** per center rule **20**.
2. When present, consult **only** that tree as default authoritative context while
   authoring (unless the user explicitly expands scope for this turn).
3. When absent, distill best-effort context and set `sotPresent: false` — do not
   pretend a maintained SoT exists.
4. **Forbidden:** creating, editing, or deleting files under **`source-of-truth/`**.
   SoT refresh is a separate mission (**`refresh source of truth`**); parent §6a
   reports deviations after this skill completes.

## Authored output hygiene (binding)

Follow center rule **20** § *Authored document output hygiene*. Consult SoT for
facts; write the document as if those facts are ordinary domain knowledge.
**Forbidden** in the target document body: naming **`source-of-truth`** / SoT, or
stating that content came from that tree. Parent §6a deviation reporting stays
in Mission Control / ops docs — not inside the deliverable.

Before marking the document complete, record whether SoT was present and whether
it was consulted so the parent can run §6a.

## Completion (spawned)

**outputs:** `documentComplete`, `relativeFilePath`, `revisionCount`, `sotPresent`,
`sotConsulted`, `continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `documentComplete` only after user confirmation; set `sotPresent` / `sotConsulted` honestly |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

Stop after the MCP result call. Do not emit another **`mission_control_spawn_agent`** on this lane.

## Completion (inline)

Report completion status, path, revision count, and SoT consult flags in prose.
