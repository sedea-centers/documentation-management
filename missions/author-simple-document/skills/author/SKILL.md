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
  markupMode:
    type: string
    description: >-
      `.docx` authoring mode — `pending` leaves track-change markup via
      docx-markup.mjs; `final` writes final-quality prose directly (default).
    required: false
    default: final
timeoutMs: 3600000
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-simple-document/plan.mdc
  - .sedea/centers/documentation-management/rules/20_source-of-truth.mdc
  - .sedea/centers/documentation-management/rules/10_required-tools.mdc
---

# Author Simple Document Author

Spawned author for **author-simple-document**. Load `planPath` and the document at
`localPath` + `relativeFilePath`. Render **Proposed Changes** into the file —
when **`markupMode: final`** (default), as final-quality prose; when
**`markupMode: pending`** on **`.docx`**, as pending markup per § *Pending markup
mode* (not final unmarked prose). Interact with the user until they confirm the
document is done. Do not edit without a plan where `planApproved` was true.

## Source of truth (binding)

1. Check for **`<localPath>/source-of-truth/`** per center rule **20**.
2. When present, consult **only** that tree as default authoritative context while
   authoring (unless the user explicitly expands scope for this turn).
2b. **Change log:** Do **not** consult **`CHANGELOG.md`** under
    **`source-of-truth/`** as authoritative context. Use it only when the
    user explicitly refers to it and explains how it should be used this turn
    (rule **20** § *Change log*).
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

## `.docx` programmatic edit contract (binding)

When **`relativeFilePath`** ends with **`.docx`** and this lane performs material
**Write** / **StrReplace** / unzip-based OOXML edits on the working file:

1. **Pre-edit backup:** `cp` the target to a timestamped **`*.bak-YYYYMMDDHHMMSS`**
   beside the file before the first material edit in the pass.
2. **OOXML-safe edits:** Prefer surgical edits inside **`word/document.xml`**
   (and related body parts). **Forbidden:** rewriting **`[Content_Types].xml`**
   or **`*.rels`** with prefixed default xmlns (**`ns0:`**, **`ns1:`**, etc.);
   preserve Word-native package relationship parts.
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
| **`final`** (default) | Write final-quality prose directly per § *`.docx` programmatic edit contract* above |
| **`pending`** | Apply pending markup via **`docx-markup.mjs`** per rule **10** § *Pending OOXML markup script* — **forbidden** committing final unmarked prose on the first substantive edit |

When **`markupMode: pending`** and **`relativeFilePath`** ends with **`.docx`**:

1. **Helper:** Invoke **`scripts/docx-markup.mjs`** (from center repo root, or
   **`CENTER_WORKTREE_ROOT/scripts/docx-markup.mjs`** under an active center
   worktree) via **`node`** — subcommands **`mark-insert`**, **`mark-delete`**,
   **`mark-red`** per edit shape; **`list-pending`** and **`accept-all`** are the
   binding inventory / flatten interface — do not substitute ad-hoc XML for those.
2. **`w:author`:** Default **`Sedea Author Agent`** (script default); pass
   **`--author`** only when dispatch explicitly overrides attribution.
3. **`w:trackRevisions`:** The script enables **`w:trackRevisions`** in
   **`word/settings.xml`** when absent — do not strip settings the script adds.
4. **Validate:** Run **`docx-ooxml-validate.sh`** after every markup mutation
   (fail closed) before setting **`markupPending`** or handing off to sync.
5. **`markupPending` output:** After substantive pending edits, run
   **`list-pending`**; set **`outputs.markupPending: true`** when JSON reports
   pending markup (`pending: true`). Set **`markupPending: false`** when
   **`list-pending`** reports no pending markup at terminal. Non-**`.docx`**
   targets omit **`markupPending`** or set **`false`**.

**Out of scope on this skill:** Outbound **`rclone`** sync, **`accept-all`**, and
parent-mission pending-markup USER_CHECKPOINT gates (PR 4) — this skill only
authors markup and reports **`markupPending`** honestly.

## Completion (spawned)

**outputs:** `documentComplete`, `relativeFilePath`, `revisionCount`, `markupMode`,
`markupPending`, `sotPresent`, `sotConsulted`, `continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `documentComplete` only after user confirmation; set `markupMode` / `markupPending` per § *Pending markup mode*; set `sotPresent` / `sotConsulted` honestly |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

Stop after the MCP result call. Do not emit another **`mission_control_spawn_agent`** on this lane.

## Completion (inline)

Report completion status, path, revision count, and SoT consult flags in prose.
