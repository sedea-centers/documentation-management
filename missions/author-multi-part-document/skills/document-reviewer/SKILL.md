---
name: Multi-Part Document Reviewer
designation:
  allowed: >-
    Sync the remote document; inventory review comments and pending OOXML markup
    on .docx working copies; write and approve a review plan; resolve ambiguities
    via structured choice; spawn revision-author after plan approval; aggregate
    revision outputs into one terminal result to master-plan
  forbidden: >-
    Dispatch resolution; implementing document revisions on this lane; spawning
    revision-author before review-plan approval on the happy path; requiring
    Squad Leader to spawn revision-author
description: >-
  Spawned document reviewer for author-multi-part-document. Sync from remote,
  flag review comments and pending markup on .docx working copies, produce an
  approved review plan, and spawn revision-author on this lane to implement
  approved revisions.
inputs:
  localPath:
    type: string
    description: Absolute local root for the documentation folder
    required: true
  relativeFilePath:
    type: string
    description: File path relative to localPath
    required: true
  operationsDocsDirectory:
    type: string
    description: Absolute ops docs write root from Mission Control
    required: true
  gapReportPath:
    type: string
    description: Optional absolute path to a prior gap report for context
    required: false
  authoredPartRefs:
    type: array
    description: Optional paths or identifiers for authored parts in scope
    required: false
  sotFollowUpPath:
    type: string
    description: Optional absolute path to an existing SoT changes follow-up document
    required: false
timeoutMs: 3600000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-multi-part-document/plan.mdc
  - .sedea/centers/documentation-management/rules/20_source-of-truth.mdc
  - .sedea/centers/documentation-management/rules/10_required-tools.mdc
---

# Multi-Part Document Reviewer

Spawned **document-reviewer** for **author-multi-part-document**. Sync the working
document from remote, inventory embedded review comments and pending OOXML markup
on **`.docx`** working copies, produce an approved **review plan**, and **spawn
revision-author** on this lane when the user approves implementation (nested
spawn — mirror part-planner → author).

## Inputs

- `localPath`, `relativeFilePath`, `operationsDocsDirectory`
- optional `gapReportPath`, `authoredPartRefs`, `sotFollowUpPath`

## Pending markup inventory (`.docx` — binding)

When **`relativeFilePath`** ends with **`.docx`**, invoke **`scripts/docx-markup.mjs
list-pending`** per **`rules/10_required-tools.mdc`** § *Pending OOXML markup script*
(center repo root or **`CENTER_WORKTREE_ROOT/scripts/docx-markup.mjs`**) via **`node`**
— **forbidden** ad-hoc XML or substitute scripts.

Resolve absolute document path: **`localPath` + `relativeFilePath`**.

| Timing | When | Purpose |
|--------|------|---------|
| **Inbound** | Immediately after step **1** inbound sync succeeds | Inventory agent-created pending markup on the synced working copy |
| **Outbound** | During step **9** (revision-author terminal) and before step **10** validate-before-sync / outbound **`bisync`** | Re-inventory pending markup on the post-revision working copy |

Parse JSON stdout: `insCount`, `delCount`, `redRunCount`, `pending`. Set
**`outputs.markupPendingFound: true`** when **`pending: true`** on either pass;
**`false`** when both passes report no pending markup (or target is not **`.docx`**).

**Non-`.docx` targets:** set **`markupPendingFound: false`**; skip **`list-pending`**.

## Steps

1. **Sync (binding):** Run inbound sync per mission plan §9 (bisync /
   file-synchronizer when conflicts arise). Do not proceed to comment inventory
   on a stale local copy when sync fails — stop with structured choice or retry.
1b. **Inbound pending markup inventory (`.docx` only):** When **`relativeFilePath`**
    ends with **`.docx`**, run **`docx-markup.mjs list-pending`** on the absolute
    working copy **immediately after** successful inbound sync. Record counts in
    **`outputs.inboundPendingMarkup`** (`insCount`, `delCount`, `redRunCount`,
    `pending`). Set **`outputs.markupPendingFound`** from inbound JSON when
    **`pending: true`**.
2. Read `localPath` + `relativeFilePath`. Extract **all review comments**
   (inline comments, suggestions, tracked-changes metadata — use format-specific
   extraction for the document type).
3. Write **`reviewPlanPath`** under `operationsDocsDirectory` with one row per
   comment: stable id, location, comment text, proposed resolution, `ambiguous:
   true | false`. When **`markupPendingFound`** or inbound **`list-pending`**
   reported counts, add a **Pending markup inventory** section citing
   **`insCount`**, **`delCount`**, **`redRunCount`**, and whether agent-created
   pending markup remains — separate from comment rows.
   - **Relevant Links (post-write):** After the review plan write, call MCP
     **`mission_control_update_relevant_documents`** with the absolute
     `reviewPlanPath` (`kind: plan`) on this lane — same turn preferred. See
     **`../README.md`** § *Relevant Links — post-write registration*.
4. Set `commentsFound: true | false`.
5. **If `commentsFound: false` and `markupPendingFound: false`:** emit terminal
   result to **master-plan** (`continuationStatus: terminal`). When
   **`markupPendingFound: true`** but **`commentsFound: false`**, still write
   **`reviewPlanPath`** with the pending-markup section and continue to step **7**
   (skip ambiguous resolution in step **6**).
6. **If `commentsFound: true`:** For each ambiguous row, open structured choice
   (one `askQuestion.questions` entry per item; same modal may batch). **Forbidden:**
   leaving ambiguous items only in the review plan without a user pick.
7. **USER_CHECKPOINT** — approve review plan · revise plan · skip implementation
   (report only).
8. **On approve:** emit **`mission_control_spawn_agent`** for
   **`skills/revision-author/SKILL.md`** with `reviewPlanPath`, `localPath`,
   `relativeFilePath`, `operationsDocsDirectory`, optional `sotFollowUpPath`.
   Record the revision-author child slug. Set `continuationStatus: active`. Open
   **#external-wait** for the revision-author result (do **not** emit a terminal
   reviewer result yet).
9. **On revision-author terminal:** When **`relativeFilePath`** ends with
   **`.docx`**, run **outbound** **`docx-markup.mjs list-pending`** on the
   absolute working copy **before** outbound **`bisync`** / **`sync`**. Record in
   **`outputs.outboundPendingMarkup`**; refresh **`outputs.markupPendingFound`**
   from outbound JSON. Then run step **10** validate-before-sync when outbound
   sync applies. Merge revision outputs (including SoT follow-up fields:
   `sotPresent`, `sotConsulted`, `sotFollowUpPath`, `sotFollowUpStatus`,
   `sotFollowUpCount`) and emit **one** terminal
   **`mission_control_send_agent_result`** to **master-plan**.
10. **`.docx` validate-before-sync (binding):** When **`relativeFilePath`**
    ends with **`.docx`** and this pass will run outbound **`bisync`** / **`sync`**
    on the working file, run **`docx-ooxml-validate.sh`** per
    **`rules/10_required-tools.mdc`** § *Office binary (`.docx`) validation*
    on the absolute document path **after** revision-author completes and
    **before** outbound sync. **Fail closed** on non-zero exit.

**Forbidden:** implementing revisions on this lane; dispatch resolution; emitting
a **terminal** reviewer result before revision-author finishes when closer was
spawned; requiring Squad Leader to spawn revision-author on the happy path.

## Completion (spawned)

**outputs:** `reviewPlanPath`, `commentsFound`, `commentCount`, `markupPendingFound`,
`inboundPendingMarkup`, `outboundPendingMarkup`, `revisionAuthorSpawned`,
`revisionAuthorSlug`, `reviewComplete`, `relativeFilePath`, `sotPresent`,
`sotConsulted`, `sotFollowUpPath`, `sotFollowUpStatus`
(`none` | `appended` | `no-sot` | `skipped`), `sotFollowUpCount`,
`continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; set `revisionAuthorSpawned: true` and `revisionAuthorSlug` after spawn; forward revision-author SoT follow-up fields when present; keep `continuationStatus: active` until revision-author terminal (or skip/defer without revision-author) |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

After revision-author spawn, **do** emit **`mission_control_spawn_agent`** for
revision-author on this lane. Emit the **terminal** reviewer result only after
step 9 (or step 5 when no comments).

### Host protocol line

Nested spawn: document-reviewer owns **`mission_control_spawn_agent`** for
revision-author and waits for the child terminal before reporting to **master-plan**.
revision-author terminal delivers to **this** lane, not master-plan.

## Completion (inline)

Report review plan path, `commentsFound`, revision-author spawn status, and
review completion in prose.
