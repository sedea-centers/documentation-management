---
name: File Synchronizer
designation:
  allowed: Compare bisync conflict artifacts; semantic resolution gates; merged write; rclone sync to remote
  forbidden: Dispatch resolution; silent overwrite without user choice on semantic conflicts
description: >-
  Compare rclone bisync conflict artifacts (.conflict1 / .conflict2), resolve
  semantic conflicts via structured choice, write the merged file, and rclone
  sync to remote.
inputs:
  relativeFilePath:
    type: string
    description: File path relative to localPath
    required: true
  localPath:
    type: string
    description: Absolute local root for the documentation folder
    required: true
  rcloneRemote:
    type: string
    description: rclone remote name for the folder
    required: true
  rcloneRemotePath:
    type: string
    description: Remote path prefix within the remote
    required: true
  operationsDocsDirectory:
    type: string
    description: Absolute ops docs write root from Mission Control
    required: true
  conflict1Path:
    type: string
    description: Absolute path to .conflict1 side file
    required: false
  conflict2Path:
    type: string
    description: Absolute path to .conflict2 side file
    required: false
  markupPending:
    type: boolean
    description: >-
      When true, outbound sync is blocked until pending markup clears. When false,
      sync may proceed. When omitted on .docx targets, the gate falls back to
      docx-markup.mjs list-pending on the local file.
    required: false
timeoutMs: 1800000
warmUpRules:
  - .sedea/centers/documentation-management/rules/00_documentation-management.mdc
  - .sedea/centers/documentation-management/missions/author-simple-document/plan.mdc
  - .sedea/centers/documentation-management/rules/10_required-tools.mdc
---

# File Synchronizer

Spawned conflict specialist for **author-simple-document**. When **`rclone bisync`**
reports both-sides-changed conflicts, locate `.conflict1` and `.conflict2`
artifacts beside the target file. Compare versions; perform smart merge when
changes are non-overlapping textual edits.

When changes are **semantic** (conflicting intent), USER_CHECKPOINT — explain
**local change intent** vs **remote change intent**, show a concise diff summary,
and ask which resolution path prevails (`local` | `remote` | `merged` via More
details). Write the final file to `localPath` + `relativeFilePath`, then run
**`rclone sync`** (not bisync) to update the remote copy.

### Pending markup outbound gate (binding)

Before any outbound **`rclone sync`** (including post-conflict sync on this
skill), enforce the PRD hard gate: **no outbound push while pending markup
exists**.

When **`relativeFilePath`** ends with **`.docx`**:

1. Resolve the absolute local file path: **`localPath` + `relativeFilePath`**.
2. Run **`scripts/docx-outbound-sync-gate.mjs`** (from center repo root, or
   **`CENTER_WORKTREE_ROOT/scripts/docx-outbound-sync-gate.mjs`**) via **`node`**:
   - Pass **`--markup-pending true`** or **`--markup-pending false`** when spawn
     **`inputs.markupPending`** is known from the upstream author lane.
   - When **`markupPending`** is omitted, invoke with the absolute **`.docx`**
     path only — the script falls back to **`list-pending`**.
3. **Fail closed** on non-zero exit — do **not** run **`rclone sync`**. Report
   that outbound sync is blocked until pending markup clears (Word accept or
   Mission Control **`accept-all`** on a later pass — PR 4 mission gates).
4. **Exit 0** only when the gate allows sync — then continue to validate-before-sync
   and Drive format pairing below.

Non-**`.docx`** targets skip this gate.

### `.docx` validate-before-sync (binding)

When **`relativeFilePath`** ends with **`.docx`**, run **`docx-ooxml-validate.sh`**
per **`rules/10_required-tools.mdc`** § *Office binary (`.docx`) validation* on
the absolute merged file path **before** outbound **`rclone sync`**. Default
invocation **auto-normalizes** GDrive/interop patterns in place (timestamped
**`.bak-*`** first) before strict validation; use **`--no-normalize`** only for
strict pre-normalize checks. **Fail closed** on non-zero exit — stderr includes
a structured error summary. **Missing `node` / `npx`:** stop and route to
**`install required tools`** on a new dispatch — do not bisync/sync first.

### Drive format pairing on outbound `rclone sync` (binding)

Before **`rclone sync`**, apply the mission plan § **Drive format pairing
(local Office ↔ native Google Docs)** (typed remote mime probe + flag table).

When the local file is **`.docx`** and the remote is a **native Google Doc**
(`application/vnd.google-apps.document`), include **`--drive-import-formats docx`**
together with the required SA / `--drive-root-folder-id` flags from
**`10_required-tools.mdc`**. Do **not** treat a refused binary upload as an auth
failure until that pair is checked. If remote type is unknown after a successful
auth probe → USER_CHECKPOINT — do not invent retry loops.

## Completion (spawned)

**outputs:** `conflictResolved`, `resolutionPath`, `syncedToRemote`, `continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

Stop after the MCP result call. Do not emit another **`mission_control_spawn_agent`** on this lane.

## Completion (inline)

Report resolution path, whether remote sync succeeded, and any remaining conflicts.
