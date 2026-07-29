---
name: Multi-Part Document Revision Author
designation:
  allowed: >-
    Apply an approved review plan to the target document; run draft→final review
    gates for material edits; consult folder source-of-truth when present; review
    the revision conversation for SoT alterations and collect approved follow-ups
  forbidden: >-
    Dispatch resolution; edits without approved reviewPlanPath; writes under
    source-of-truth/; planning other parts or review passes; spawning siblings
description: >-
  Spawned revision author for author-multi-part-document (spawned by
  document-reviewer). Implement approved review-plan rows, handle draft→final
  review when needed, and collect SoT follow-ups after revisions complete.
inputs:
  reviewPlanPath:
    type: string
    description: Absolute path to the approved review plan
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
  sotFollowUpPath:
    type: string
    description: >-
      Optional absolute path to the SoT changes follow-up document under
      operationsDocsDirectory; when omitted, create or reuse the default
      `<slug-or-doc>-sot-changes-follow-up.md` in that directory
    required: false
timeoutMs: 3600000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-multi-part-document/plan.mdc
  - .sedea/centers/documentation-management/rules/20_source-of-truth.mdc
---

# Multi-Part Document Revision Author

Spawned **revision-author** for **author-multi-part-document** (normally by
**document-reviewer**). Load `reviewPlanPath` where the review plan was approved,
then apply each approved row to `localPath` + `relativeFilePath`. Mirror the
**author** lane draft→final and SoT conversation-review contracts.

## Inputs

- `reviewPlanPath` — approved review plan binding
- `localPath`, `relativeFilePath` — target document
- `operationsDocsDirectory` — ops docs root from Mission Control
- `sotFollowUpPath` — optional SoT changes follow-up document path

## Steps

1. Verify `reviewPlanPath` exists and reflects an approved review plan.
2. Read the target document; load approved rows from the review plan.
3. Source of truth (binding): same as `skills/author/SKILL.md` step 3 — consult
   **`<localPath>/source-of-truth/`** when present; **forbidden** writes under it;
   do not treat **`CHANGELOG.md`** as authoritative unless the user explicitly
   names it.
4. Authored output hygiene (binding): Follow center rule **20** § *Authored
   document output hygiene*.
5. **Implement review-plan rows:** Apply each approved resolution. When edits are
   material, run the **draft→final** structured-choice chain (mirror author step
   5): draft write → draft review gate → final copy → revision-complete gate.
   **Forbidden:** skipping draft review for large substantive rewrites.
   - **Relevant Links (post-write):** After each Write/StrReplace that
     **materially edits** the working document at `localPath` +
     `relativeFilePath`, call MCP
     **`mission_control_update_relevant_documents`** with the absolute document
     path (`kind: other`) — same turn preferred. **Skip** unchanged
     already-registered paths. See **`../README.md`** § *Relevant Links —
     post-write registration*.
6. **Revision-complete USER_CHECKPOINT** — after all approved rows are implemented
   (or explicitly deferred with rationale recorded). Options at minimum:
   **Confirm revisions complete** · **Revise** · **Defer remaining rows** · then
   the universal trailer.
7. **Direct user SoT requests (binding):** When the user explicitly requests a SoT
   change during this pass, append to the SoT changes follow-up document. Do **not**
   write under **`source-of-truth/`**.
   - **Relevant Links (post-write):** After creating or materially editing the
     SoT follow-up document, call MCP
     **`mission_control_update_relevant_documents`** with its absolute path
     (`kind: other`) — same turn preferred. See **`../README.md`** § *Relevant
     Links — post-write registration*.
8. After the user confirms revisions complete (step 6), **before** the terminal MCP
   result, run **SoT conversation review** (mirror author step 8):
   - Review this pass's conversation and authored delta against consulted SoT.
   - Enumerate candidate follow-ups where SoT content was altered in practice.
   - One structured-choice question per identified change (batched modal allowed).
   - Append approved items to the SoT changes follow-up document.
   - **Relevant Links (post-write):** After conversation-review writes to the
     SoT follow-up document, call MCP
     **`mission_control_update_relevant_documents`** with its absolute path when
     not already registered this session with no content change — same turn
     preferred.
   - **Zero-candidate USER_CHECKPOINT** when no candidates — same contract as author
     step 8.6.
9. Record `reviewComplete: true` only after step 6 confirmation and step 8
   completes (including zero-candidate gate when applicable).

**SoT follow-up document path:** Use `sotFollowUpPath` when provided; otherwise
create or reuse
`{operationsDocsDirectory}/<document-slug>-sot-changes-follow-up.md`.

**Forbidden:** dispatch resolution; writing under **`source-of-truth/`** on this
lane; treating SoT follow-up approval as authorization to edit SoT **here**
(Squad Leader applies per **`plan.mdc`** §6a after document-reviewer terminal).

## Completion (spawned)

**outputs:** `reviewPlanPath`, `reviewComplete`, `relativeFilePath`, `rowsApplied`,
`rowsDeferred`, `sotPresent`, `sotConsulted`, `sotFollowUpPath`, `sotFollowUpStatus`
(`none` | `appended` | `no-sot` | `skipped`), `sotFollowUpCount`, `continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `reviewComplete` only after user confirmation and SoT conversation review completes per step 8 |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |
| R5 | SoT conversation review complete: durable review section written; zero-candidate USER_CHECKPOINT passed before terminal MCP |

Stop after the MCP result call. Terminal delivers to the **document-reviewer**
parent lane — not Squad Leader. Do not emit another **`mission_control_spawn_agent`**
on this lane.

## Completion (inline)

Report review plan path, completion status, rows applied/deferred, path, SoT
consult flags, and SoT follow-up status in prose.
