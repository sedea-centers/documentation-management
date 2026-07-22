---
name: PDF Converter
designation:
  allowed: >-
    Convert DOCX or native Google Doc to PDF via Drive import/export; write PDF
    only to approved outputDirectory; delete temporary Drive artifacts
  forbidden: >-
    Dispatch resolution; overwrite or rename source; skip temporary cleanup;
    invent secrets or expose service-account material; run folder bisync
description: >-
  Spawned PDF converter for convert-document. Convert source to PDF without
  replacing the source; support documentation-folder-sync and operations-result
  output modes for caller missions.
inputs:
  sourcePath:
    type: string
    description: Absolute local path to the source document
    required: true
  sourceKind:
    type: string
    description: docx | native-google-doc | auto
    required: true
  outputMode:
    type: string
    description: documentation-folder-sync | operations-result
    required: true
  outputDirectory:
    type: string
    description: Absolute directory for the generated PDF
    required: true
  outputFilename:
    type: string
    description: PDF filename (default source basename with .pdf)
    required: false
  folderSlug:
    type: string
    description: Registered documentation folder slug when applicable
    required: false
  rcloneRemote:
    type: string
    description: rclone remote name for the folder
    required: false
  rcloneRemotePath:
    type: string
    description: Remote path prefix within the remote
    required: false
  operationsDocsDirectory:
    type: string
    description: Absolute ops docs write root from Mission Control
    required: true
timeoutMs: 1800000
warmUpRules:
  - .sedea/centers/documentation-management/missions/convert-document/plan.mdc
  - .sedea/centers/documentation-management/rules/00_documentation-management.mdc
  - .sedea/centers/documentation-management/rules/10_required-tools.mdc
---

# PDF Converter

Spawned **pdf-converter** for **convert-document**. Convert `sourcePath` to PDF
without changing or replacing the source. Callers choose `outputMode` and
destination before spawn.

## Inputs

- `sourcePath`, `sourceKind` (`docx` | `native-google-doc` | `auto`)
- `outputMode` (`documentation-folder-sync` | `operations-result`)
- `outputDirectory`, optional `outputFilename`
- optional folder/rclone fields; `operationsDocsDirectory`

## Steps

1. Resolve `sourceKind`. When `auto`, probe whether the source is a native
   Google Doc vs local DOCX (typed remote mime probe when folder/rclone fields
   are present).
2. Resolve `outputFilename` (default: source basename with `.pdf`). Confirm
   write target is under `outputDirectory` only.
3. **Native Google Doc:** skip DOCX import; export with
   `--drive-export-formats pdf` plus required service-account / root-folder
   flags from center rule **10**.
4. **DOCX:** create a unique temporary Shared Drive folder; upload with
   `--drive-import-formats docx` plus the same required flags; export PDF from
   the temporary Google document.
5. Validate a non-empty PDF file; write only under `outputDirectory`.
6. **Cleanup (binding):** delete temporary Google artifacts. Set
   `temporaryRemoteDeleted: true` only when confirmed; otherwise report cleanup
   failure in `errors` / warnings.
7. Set `sourcePreserved: true` on success. Collect `conversionWarnings` for
   fonts, pagination, tracked changes, fields, and macros.
8. Do **not** run rclone bisync — callers that chose
   `documentation-folder-sync` own post-PDF sync.

**Forbidden:** overwriting or renaming the source; skipping temp cleanup;
exposing secrets; calling `mission_control_propose_dispatch_resolution`.

## Completion (spawned)

**outputs:** `pdfPath`, `pdfRef`, `sourcePreserved`, `temporaryRemoteDeleted`,
`conversionWarnings`, `outputMode`, `continuationStatus`

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list above; `sourcePreserved` must be `true` on success |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session; host resolves **`correlationId`**) |

Stop after the MCP result call. Do not emit another **`mission_control_spawn_agent`** on this lane.

## Completion (inline)

Report `pdfPath` / `pdfRef`, preservation and cleanup flags, warnings, and
`outputMode` in prose.
