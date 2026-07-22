---
name: Document Scaffolder
designation:
  allowed: >-
    Create-mode intake (author-new-template, existing template, shape-from-kind);
    destination folder override; template and shape iteration; scaffold write
    under bound localPath
  forbidden: Dispatch resolution; bisync; planning or authoring without parent handover
description: >-
  Collect create mode, filename, destination folder, optional existing template
  or document shape, user approval, and write the initial scaffold (standard
  document or new template) under the bound documentation folder.
inputs:
  folderSlug:
    type: string
    description: Registered folder slug from documentation-management.yaml
    required: true
  localPath:
    type: string
    description: Absolute local root for the documentation folder
    required: true
  operationsDocsDirectory:
    type: string
    description: Absolute ops docs write root from Mission Control
    required: true
  subfolder:
    type: string
    description: >-
      Optional relative subfolder under localPath. When omitted for author-new-template
      mode, default to templates.
    required: false
  templatePath:
    type: string
    description: Optional absolute or workspace-relative template file path
    required: false
timeoutMs: 900000
warmUpRules:
  - .sedea/centers/documentation-management/rules/00_documentation-management.mdc
  - .sedea/centers/documentation-management/missions/author-simple-document/plan.mdc
---

# Document Scaffolder

Spawned specialist for **author-simple-document** intent **`create`**. Open create
intake, then walk filename/placement, shape or template resolution, approval, and
write under `localPath` (respecting `subfolder`).

**Standard documents stay available:** **Use existing template** and **No template /
shape from kind** remain first-class options alongside **Author new template —
I'll explain how**. Do not collapse create into template-only.

## Steps

1. **Create-mode intake** — USER_CHECKPOINT (include **More details for option _**):
   - **Author new template — I'll explain how** — user describes how the template
     should work; agent proposes template shape; after approval, write a **new
     template** file. Default `subfolder` = **`templates`** when spawn `subfolder`
     is omitted.
   - **Use existing template** — user supplies `templatePath`; scaffold a
     **standard document** from that template (non-template outcome).
   - **No template / shape from kind** — gather file type and document kind
     (invoice, consulting contract, memo, …); propose section outline; write a
     **standard document** (non-template outcome).
   - **Change destination folder** — override relative subfolder under `localPath`
     (for author-new-template, away from default **`templates/`**; for standard
     documents, set or clear optional placement). May be co-presented with mode
     picks or offered as a follow-up gate before write.
2. **Filename and placement** — structured choice or More details for basename;
   apply `subfolder` (default **`templates`** only for author-new-template when
   unset). Confirm destination before write when the user changed it.
3. **Shape / template resolution**
   - **Author new template** — free-form description → propose template structure
     (each section with a brief purpose); iterate until approved (USER_CHECKPOINT
     per revision).
   - **Use existing template** — resolve `templatePath`; confirm before write.
   - **No template / shape from kind** — propose structure from document kind;
     iterate until approved (USER_CHECKPOINT per revision).
4. **Write scaffold** — create `relativeFilePath` under `localPath` (+ `subfolder`);
   set `scaffoldKind` to `template` or `document`. Do not commit to hosting git
   (folder is gitignored per center rules).

## Completion (spawned)

**outputs:** `relativeFilePath`, `scaffoldWritten`, `scaffoldKind`, `documentKind`,
`continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `scaffoldKind` is `template` or `document` |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

Stop after the MCP result call. Do not emit another **`mission_control_spawn_agent`** on this lane.

## Completion (inline)

Report `relativeFilePath`, whether scaffold was written, `scaffoldKind`, and
document kind in prose.
