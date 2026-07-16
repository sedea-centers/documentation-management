---
name: Configure gcloud Drive
description: >-
  Confirm GCP console access, authenticate gcloud (user terminal), configure
  GCP project and service account, enable Drive API, apply rclone Drive
  access, provision Internal Desktop OAuth client_id into rclone config, and
  verify.
inputs:
  projectPreference:
    type: string
    description: select-existing | create-default
    required: true
  existingProjectId:
    type: string
    description: Project id when selecting an existing project
    required: false
  defaultNewProjectId:
    type: string
    description: Default new project id/name when creating
    required: true
    default: sedea-agent-squad
  serviceAccountPreference:
    type: string
    description: select-existing | create-default
    required: true
  existingServiceAccountEmail:
    type: string
    description: Service account email when selecting existing
    required: false
  defaultNewServiceAccountId:
    type: string
    description: >-
      Default new SA account id — hosting-repo basename + -sedea-agent
      (e.g. centers-development-hosting-repo-sedea-agent)
    required: true
  credentialsTargetPath:
    type: string
    description: Absolute path under user home for the SA JSON key file
    required: true
  operationsDocsDirectory:
    type: string
    description: Absolute ops docs write root from Mission Control
    required: true
  rcloneRemote:
    type: string
    description: rclone remote name to receive client_id/client_secret
    required: false
    default: sedea-gdrive
timeoutMs: 1800000
warmUpRules:
  - .sedea/centers/documentation-management/rules/10_required-tools.mdc
  - .sedea/centers/documentation-management/missions/required-tools-installation/plan.mdc
---

# Configure gcloud Drive

Spawned specialist for Documentation Management: after the **gcloud** CLI is
available, confirm the user can open Google Cloud in the browser, authenticate
in the terminal, configure a GCP project and service account, enable Google
Drive API, apply rclone-compatible Drive access, provision an **Internal**
Desktop OAuth client for rclone (write `client_id` / `client_secret` into
rclone config — never into chat), and verify.

**Invoker:** parent mission **`required-tools-installation`** §7
(`execution: spawned`).

**Script (Unix):** [../scripts/setup-rclone-drive-client-id.sh](../scripts/setup-rclone-drive-client-id.sh)
— invoked from this skill after SA + Drive access are ready.
**Windows:** `setup-rclone-drive-client-id.ps1` is a **follow-up PR** — on
Windows, record `rcloneClientConfigured: false` with a clear gap and do not
pretend the Unix script ran.

## Preconditions

- `gcloud` resolves on PATH (parent §2–§6 / registry). If missing → terminal
  **`failure`** — do not install the CLI in this skill.
- Mission Control lane with structured choice and MCP result tools.

## Steps

### 1. Confirm GCP access, then authenticate gcloud (user — binding)

1. Probe auth: `gcloud auth list` (or equivalent). If an active authenticated
   account exists → continue to step 2.
2. If **not** authenticated, do **these checks in order** before any project
   or service-account work:

#### 1a. Make sure Google Cloud is available for their account (browser)

Present short, friendly instructions (paraphrase freely; keep the checklist):

1. Open **[https://console.cloud.google.com/](https://console.cloud.google.com/)** in a browser
   (sign in with the Google account they will use for this setup).
2. Confirm they can reach the **Google Cloud console / dashboard** (not an
   error page or a blocked-org screen).
3. If the page pushes **“Try for free”** / **“Try for free now”** (or similar
   free-trial signup), they should complete that flow **or** use an org that
   already has Google Cloud enabled — until the normal Cloud dashboard is
   usable, `gcloud` login and project creation will fail.
4. If their **organization** manages Google Cloud, they may need an admin to
   turn on Cloud for their user; the skill cannot do that for them.

Open an **external-wait / next-step** structured choice before ending the turn,
for example: **Dashboard looks good — continue to login**, **Still blocked /
need help**, **Abort**, **More details for option _**. Do **not** proceed to
`gcloud auth login` until the user selects a continue path that means the
dashboard is usable.

#### 1b. Sign in with gcloud in the terminal

After 1a succeeds:

1. Ask them to open the integrated terminal with **Ctrl+`** (Control +
   backtick).
2. Ask them to run: **`gcloud auth login`** and finish the browser/device
   flow that gcloud prints.
3. **Forbidden:** running interactive `gcloud auth login` in the agent shell
   for the user.
4. Open an **external-wait / next-step** structured choice before ending the
   turn, for example: **Auth done — continue**, **Retry probe**, **Abort**,
   **More details for option _**.
5. Resume only after they select a continue path; re-probe auth before
   proceeding. If still unauthenticated → ask once more or abort per their
   choice.

### 2. Confirm gcloud CLI

Re-check `command -v gcloud` (or user-supplied path / registry install path
from parent handover). If missing → **`failure`** with message that CLI
install belongs to the parent mission registry flow.

### 3. Select or create GCP project

1. List accessible projects (`gcloud projects list`).
2. USER_CHECKPOINT — select an **existing** project **or** create default
   **`sedea-agent-squad`** (use `inputs.defaultNewProjectId`, normally
   `sedea-agent-squad`).
3. On **create**: confirm the id/name in structured choice **before**
   `gcloud projects create`. Do not create silently.
4. Set the active project for subsequent commands
   (`gcloud config set project <id>` or `--project` flags).

### 4. Select or create service account; download JSON

1. List service accounts in the chosen project.
2. USER_CHECKPOINT — select an **existing** SA **or** create default
   **`inputs.defaultNewServiceAccountId`**
   (`<hosting-repo-basename>-sedea-agent`).
3. On **create**: confirm the account id in structured choice before
   `gcloud iam service-accounts create`.
4. Create a JSON key and write it to **`inputs.credentialsTargetPath`**
   (absolute path under the user home gcloud credentials location). Create
   parent directories as needed. Do not commit the JSON to git.

### 5. Enable Google Drive API

Run:

```bash
gcloud services enable drive.googleapis.com --project "<projectId>"
```

Record success/failure. Hard failure → USER_CHECKPOINT retry / abort.

### 6. Apply rclone Google Drive access for the SA

Follow [rclone Google Drive — Service Account support](https://rclone.org/drive/)
(and current Google Admin / Cloud Console UI). Typical requirements:

| Requirement | Notes |
|-------------|--------|
| Drive API enabled | Step 5 |
| SA JSON key | Step 4 → `credentialsTargetPath` |
| Access to target Drive data | Share the target folder/Shared Drive with the SA email, **or** configure domain-wide delegation with scope `https://www.googleapis.com/auth/drive` when the org requires impersonation |
| Shared Drive roles | When using Shared Drives, SA often needs **Manager** (not only Content Manager) for some rclone flags |

Prefer automatable `gcloud` IAM / sharing steps when the user’s org allows them.
When domain-wide delegation or Admin Console steps are required, open an
**external-wait / next-step** modal with the exact console steps, then resume
after the user confirms.

Record what was applied in `permissionsApplied`.

### 7. Provision rclone own Desktop `client_id` (script — binding)

rclone’s **shared** Google Drive `client_id` is retiring during 2026. New Drive
remotes must use an operator-owned OAuth client. This step **automates** that
provisioning using authenticated **gcloud** + the SA JSON from step 4.

**Canonical guide:** [Making your own client_id](https://rclone.org/drive/#making-your-own-client-id)

**Preconditions for this step (fail closed):**

1. Active `gcloud` user account (step 1).
2. SA JSON exists at `credentialsTargetPath` and Drive access from step 6 is applied.
3. Unix (macOS/Linux) for the shipped script. On **Windows**, skip script
   execution, set `rcloneClientConfigured: false`, document that
   `setup-rclone-drive-client-id.ps1` is a follow-up PR, and continue to verify
   SA-only outcomes — **do not** invent a console paste-secrets path in chat.

**Unix procedure:**

1. Resolve script path relative to this skill:
   `missions/required-tools-installation/scripts/setup-rclone-drive-client-id.sh`
   under the active center worktree or primary center checkout.
2. Run (example — substitute resolved paths; never log secrets):

```bash
bash "<script>" \
  --project-id "<projectId>" \
  --credentials-path "<credentialsTargetPath>" \
  --rclone-remote "<rcloneRemote>"
```

3. OAuth consent must be **Internal** (script sets `orgInternalOnly` when the
   API allows; confirm Internal in Console only if the patch is rejected).
4. Script writes `client_id` / `client_secret` **directly into rclone config**
   and a local `oauth-client.json` under
   `~/.config/sedea/documentation-management/` (mode 600).
5. **Forbidden:** printing `client_secret`, oauth JSON, or rclone config dump
   into chat, `displayMarkdown`, or ops docs; asking the user to paste secrets
   from chat into rclone.

USER_CHECKPOINT on script exit ≠ 0 — retry script · abort · More details.

Record `rcloneClientConfigured`, `rcloneRemote`, `oauthStorePath` from script
stdout keys (non-secret). Do **not** copy secret values into skill outputs.

### 8. Verify

1. Confirm SA path still exists; optionally re-check Drive API enablement.
2. When `rcloneClientConfigured: true`, verify the remote has a non-empty
   `client_id` via `rclone config dump` parsed in-process — **do not** print
   the dump (it may include `client_secret`).
3. Run a verification command that exercises gcloud against Drive in this
   configuration. Record `verifyCommand`, exit code, and `verifyPassed`.

USER_CHECKPOINT on failure — retry / accept partial / abort.

**Note:** Browser OAuth for the rclone remote (`rclone config reconnect`) is
owned by **new-documentation-folder-configuration** (or an explicit user
terminal step) — this skill must not run interactive rclone auth in the agent
shell.

### 9. Complete (spawned)

Call MCP **`mission_control_send_agent_result`** once (see below). **Do not**
call **`mission_control_propose_dispatch_resolution`** (Squad Leader only).

## Completion (spawned)

### Required outputs

| Field | Type | Meaning |
|-------|------|---------|
| `projectId` | string | Chosen or created project id |
| `serviceAccountEmail` | string | Chosen or created SA email |
| `credentialsPath` | string | Absolute path to SA JSON |
| `driveApiEnabled` | boolean | Drive API enable result |
| `permissionsApplied` | string | Summary of rclone-related SA access steps |
| `rcloneClientConfigured` | boolean | Whether Desktop client_id was written into rclone config |
| `rcloneRemote` | string | rclone remote name updated/created |
| `oauthStorePath` | string | Local oauth-client.json path (not secret contents) |
| `verifyCommand` | string | Verification command run |
| `verifyPassed` | boolean | Whether verification passed |
| `continuationStatus` | string | `terminal` when this skill session is done |

### Errors

Populate **`errors`** as `{ "message": "..." }[]`; use `[]` when none.
**Forbidden** in errors/summary: client secrets, SA private keys, oauth JSON bodies.

### Host protocol line (MCP result)

Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**,
optional **`outputs`** / **`errors`**. **Forbidden:** agent-authored
**`correlationId`**, **`dispatchId`**, **`slotId`**, or other host identity
keys — the host injects identity.

## Completion (inline)

Same semantic fields as spawned **`outputs`**, reported in prose to the
invoker. **No** MCP spawn/result tools unless the invoker switched to spawned
mode. **Never** include secret values in prose.
