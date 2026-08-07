---
name: Multi-Part Document Author
designation:
  allowed: >-
    Render an approved part plan into the target document as final-quality prose;
    run part-complete review gates; consult folder source-of-truth when present;
    apply plan-revision notifies from part-planner; review the part conversation
    for SoT alterations, record durable review evidence (including zero
    candidates), and collect approved SoT follow-ups
  forbidden: >-
    Dispatch resolution; edits without approved partPlanPath; writes under
    source-of-truth/; planning other parts; spawning siblings
description: >-
  Spawned author for one approved part plan under author-multi-part-document
  (spawned by part-planner). Apply the part plan, handle plan revisions from the
  planner, and collect SoT follow-ups after part completion.
inputs:
  partPlanPath:
    type: string
    description: Absolute path to the approved part plan
    required: true
  partId:
    type: string
    description: Stable part id from the master plan
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
  markupMode:
    type: string
    description: >-
      `.docx` authoring mode — `pending` leaves track-change markup via
      docx-markup.mjs; `final` writes final-quality prose directly (default).
    required: false
    default: final
timeoutMs: 3600000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-multi-part-document/plan.mdc
  - .sedea/centers/documentation-management/rules/20_source-of-truth.mdc
  - .sedea/centers/documentation-management/rules/10_required-tools.mdc
---

# Multi-Part Document Author

Spawned **author** for **author-multi-part-document** (normally by
**part-planner**). Load `partPlanPath` where the part plan was approved, then
render that part into `localPath` + `relativeFilePath` as **final-quality**
prose, then run the **part-complete** review gate (step 5) until the user
confirms **this part** is done — not the whole multi-part document.

## Inputs

- `partPlanPath`, `partId` — approved part plan binding
- `localPath`, `relativeFilePath` — target document
- `operationsDocsDirectory` — ops docs root from Mission Control
- `sotFollowUpPath` — optional SoT changes follow-up document path

## `.docx` programmatic edit contract (binding)

When **`relativeFilePath`** ends with **`.docx`** and this lane performs material
**Write** / **StrReplace** / unzip-based OOXML edits on the working file:

1. **Pre-edit backup:** `cp` the target to a timestamped **`*.bak-YYYYMMDDHHMMSS`**
   beside the file before the first material edit in the pass.
2. **OOXML-safe edits:** Prefer surgical edits inside **`word/document.xml`**
   (and related body parts). **Forbidden:** rewriting **`[Content_Types].xml`**
   or **`*.rels`** with prefixed default xmlns (**`ns0:`**, **`ns1:`**, etc.);
   preserve Word-native package relationship parts. Remove stray Google Docs
   **`goog_rdk_*`** SDTs when touching document body markup.
3. **Validate before sync:** Before outbound **`rclone bisync`** / **`sync`**, run
   **`docx-ooxml-validate.sh`** per
   **`rules/10_required-tools.mdc`** § *Office binary (`.docx`) validation*.
   **Fail closed** on non-zero exit.
4. **Missing `node` / `npx`:** Stop; tell the user to start **`install required
   tools`** on center **`documentation-management`** in a **new dispatch**.

## Pending markup mode (binding)

Resolve **`markupMode`** from spawn **`inputs`** — **`final`** when omitted or
unrecognized. Echo resolved mode in terminal **`outputs.markupMode`**.

| Mode | `.docx` substantive edits |
|------|---------------------------|
| **`final`** (default) | Write final-quality prose per step **5** below |
| **`pending`** | Apply pending markup via **`docx-markup.mjs`** per rule **10** § *Pending OOXML markup script* — **forbidden** committing final unmarked prose on the first substantive edit for this part |

When **`markupMode: pending`** and **`relativeFilePath`** ends with **`.docx`**:

1. **Helper:** Invoke **`scripts/docx-markup.mjs`** (center repo root or
   **`CENTER_WORKTREE_ROOT/scripts/docx-markup.mjs`**) via **`node`** —
   **`mark-insert`**, **`mark-delete`**, **`mark-red`** per edit shape;
   **`list-pending`** / **`accept-all`** are binding — no ad-hoc substitutes.
2. **`w:author`:** Default **`Sedea Author Agent`**; **`--author`** only when
   dispatch explicitly overrides.
3. **`w:trackRevisions`:** Script enables **`w:trackRevisions`** in settings when
   absent — preserve script-added settings.
4. **Validate:** **`docx-ooxml-validate.sh`** after every markup mutation (fail
   closed).
5. **`markupPending` output:** After substantive pending edits, run
   **`list-pending`**; set **`outputs.markupPending: true`** when JSON reports
   pending markup. Set **`false`** when no pending markup at terminal.

**Out of scope on this skill:** Outbound sync, **`accept-all`**, and parent
mission pending-markup USER_CHECKPOINT (PR 4) — report **`markupPending`** only.

## Steps

1. Verify `partPlanPath` exists and reflects an approved part plan for `partId`.
2. Read the target document; locate the insertion/update region for this part.
   - **Relevant Links (pre-edit — binding):** Before the **first**
     Write/StrReplace on `localPath` + `relativeFilePath` in this spawn
     session, call MCP **`mission_control_update_relevant_documents`** with
     the absolute working document path (`kind: other`; optional **`label`**
     with `partId`) — same turn preferred. **Forbidden:** material edit
     before this first registration when the path is not yet registered this
     session. See **`../README.md`** § *Relevant Links — registration*.
3. Source of truth (binding):
   - When **`<localPath>/source-of-truth/`** exists, consult it as default
     authoritative context (center rule **20**), **excluding `CHANGELOG.md`**.
   - **Change log:** Do not consult **`CHANGELOG.md`** as SoT unless the user
     explicitly refers to it and explains how to use it this turn.
   - **Forbidden:** create, edit, or delete under **`source-of-truth/`**.
   - When absent, set `sotPresent: false` honestly.
4. Authored output hygiene (binding): Follow center rule **20** § *Authored
   document output hygiene*. Consult SoT for facts; **forbidden** in the target
   document body: naming **`source-of-truth`** / SoT, or stating that content
   came from that tree.
5. **Final-write → part-complete review (binding):** Apply the approved part plan
   into the document — when **`markupMode: final`** (default), as **final-quality**
   prose (rule **20** hygiene); when **`markupMode: pending`** on **`.docx`**, as
   pending markup per § *Pending markup mode* — then run the part-complete gate.
   1. Write (or revise) the part region — finals when **`final`**, pending markup
      when **`pending`** — on the first substantive write for this part.
      - **Relevant Links (after material edit):** After each Write/StrReplace that
        **materially edits** the working document at `localPath` +
        `relativeFilePath`, call MCP **`mission_control_update_relevant_documents`**
        with the absolute document path (`kind: other`; optional **`label`** with
        `partId`) — same turn preferred. **Skip** unchanged already-registered
        paths (step 2 pre-edit satisfies the first registration). See
        **`../README.md`** § *Relevant Links — registration*.
   2. **Part-complete USER_CHECKPOINT** — after finals exist. Options at minimum:
      **Confirm part complete** · **Revise** · **Defer** · then the universal
      trailer.
   3. On **Revise**: apply feedback, rewrite finals, and re-open the
      part-complete gate (substep 2) — do not skip review.
   4. Loop substeps 1–3 for further sections of this part as needed until the
      user confirms part complete or defers.
6. **Plan-revision receive (binding):** When part-planner delivers a plan-change
   notification or updated `partPlanPath`, re-read the part plan, reconcile in
   progress work, and continue — do **not** wait for Squad Leader to re-spawn
   this lane. Prefer structured choice only when the revision needs a user pick.
   After reconciling, rewrite affected regions as finals and re-open the
   part-complete gate before terminal.
7. **Direct user SoT requests (binding):** When the user explicitly requests a
   SoT change during this part, append it to the **SoT changes follow-up
   document** under `operationsDocsDirectory` (create the file when missing).
   - **Relevant Links (post-write):** After creating or materially editing the
     SoT follow-up document, call MCP
     **`mission_control_update_relevant_documents`** with its absolute path
     (`kind: other`) — same turn preferred. See **`../README.md`** § *Relevant
     Links — post-write registration*.
   Do **not** write under **`source-of-truth/`**.
8. After the user confirms the part is complete (step 5 part-complete gate),
   **before** the terminal MCP result, run **SoT conversation review**:
   1. Review this part’s conversation and authored delta against consulted SoT.
   2. Enumerate candidate follow-ups where SoT content was altered in practice
      (or should be updated to match authored truth).
   3. For **each** identified change: open structured choice with **one
      `askQuestion.questions` entry per change** (same modal may batch). Options
      at minimum: approve → append to SoT follow-up doc · skip · revise wording —
      then the universal trailer.
   4. Append **approved** items to the same SoT changes follow-up document used
      for direct user SoT requests. Conversation-derived rows are **additive**,
      not a replacement.
   5. **Always record review outcome (binding):** Before setting
      `sotFollowUpStatus` or emitting terminal MCP result, write or update the
      SoT changes follow-up document with a **Conversation review — {partId}**
      section that includes: `sotPresent`, `sotConsulted`, candidate count (may
      be **0**), and a one-line rationale when count = 0. **Forbidden:** terminal
      result without this durable record when review ran.
      - **Relevant Links (post-write):** After that write or update, call MCP
        **`mission_control_update_relevant_documents`** with the SoT follow-up
        absolute path when not already registered this session with no content
        change — same turn preferred.
   6. **Zero-candidate USER_CHECKPOINT (binding):** When step 2 finds **no**
      candidates (including when `sotPresent: false`), open structured choice
      **before** `mission_control_send_agent_result`. Options at minimum:
      **Accept none — review complete, zero proposals** · **Nominate follow-up
      loci** · **Re-diff / challenge review** · then the universal trailer. Set
      `sotFollowUpStatus: none` or `no-sot` **only after** the developer picks
      **Accept none** (or after nominate/re-diff resolves with zero approved
      rows). **Forbidden:** agent-only short-circuit from “matches SoT” without
      this gate.
   7. **Status semantics:** `none` / `no-sot` means **review ran; zero approved
      proposals** — not “review skipped”. Reflect that in `summary` and
      `outputs`.
9. Record `partComplete: true` only after explicit user confirmation at the
   step 5 part-complete gate and after step 8 completes (including zero-candidate
   USER_CHECKPOINT when applicable).

**SoT follow-up document path:** Use `sotFollowUpPath` when provided; otherwise
create or reuse
`{operationsDocsDirectory}/<document-or-part-slug>-sot-changes-follow-up.md`.
Each row should name locus, proposed SoT change, source (`user-direct` |
`conversation-review`), and approval status.

**Not the change log:** The follow-up file under **`operationsDocsDirectory`**
is the proposal queue until the Squad Leader applies approved rows per
**`plan.mdc`** §6a. In-folder **`CHANGELOG.md`** is appended when the Squad
Leader applies those writes (rule **20**).

**Forbidden:** authoring other parts in the same pass without a new spawn;
calling `mission_control_propose_dispatch_resolution`; writing under
**`source-of-truth/`** on this lane; treating SoT follow-up approval as
authorization to edit SoT **here** (Squad Leader applies per **`plan.mdc`** §6a
after part-planner terminal); appending to **`source-of-truth/CHANGELOG.md`** on
this lane; treating the change log as default SoT consult material; separate
draft-review modal; *Approve draft → write final copy*; *Skip — treat current
text as final*; offering **Confirm part complete** before finals exist.

## Completion (spawned)

**outputs:** `partId`, `partComplete`, `relativeFilePath`, `markupMode`,
`markupPending`, `sotPresent`, `sotConsulted`, `sotFollowUpPath`, `sotFollowUpStatus`
(`none` | `appended` | `no-sot` | `skipped`), `sotFollowUpCount`, `continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `partComplete` only after user confirmation and SoT conversation review completes per step 8; set `markupMode` / `markupPending` per § *Pending markup mode* |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |
| R5 | SoT conversation review complete: durable **Conversation review — {partId}** section written; zero-candidate USER_CHECKPOINT passed (or per-change gates completed) before terminal MCP |

Stop after the MCP result call. Do not emit another **`mission_control_spawn_agent`** on this lane.

## Completion (inline)

Report `partId`, completion status, path, SoT consult flags, and SoT follow-up
status in prose.
