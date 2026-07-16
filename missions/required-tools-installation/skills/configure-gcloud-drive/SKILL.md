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
      Preferred new SA account id seed (6–30 chars, GCP limit). Prefer a short
      form such as centers-dev-sedea-agent. Agents MUST auto-shorten any seed
      longer than 30 chars before create — do not advertise or create
      <full-hosting-repo-basename>-sedea-agent when that exceeds 30.
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

- `gcloud` is available after **Agent shell bootstrap** below (registry install
  path counts — bare `command -v gcloud` alone is **not** enough to declare
  missing). If still missing after bootstrap → terminal **`failure`** — do not
  install the CLI in this skill.
- Mission Control lane with structured choice and MCP result tools.

## Agent shell bootstrap (binding — every turn that runs gcloud)

Before any `gcloud` / org-policy / keys / Drive command in the **agent** shell:

```bash
export PATH="${HOME}/google-cloud-sdk/bin:${HOME}/bin:${PATH}"
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
```

1. Prefer probing **`${HOME}/google-cloud-sdk/bin/gcloud`** when present.
2. **Forbidden:** hanging on interactive gcloud prompts (`API … not enabled.
   Would you like to enable and retry (y/N)?`). Always keep
   `CLOUDSDK_CORE_DISABLE_PROMPTS=1`; pre-enable APIs with
   `gcloud services enable …` instead of answering `y`.
3. Re-apply PATH + disable-prompts at the start of each substantive shell
   block — agent PATH often lacks the registry install.

## Hardened control-flow (summary)

```text
PATH bootstrap + CLOUDSDK_CORE_DISABLE_PROMPTS=1
probe gcloud (registry path first)
  → auth list; if empty → external-wait login (unavoidable)
  → list/create project (checkpoint only if preference ambiguous)
  → derive legal SA account id (auto-shorten ≤30; no checkpoint for length alone)
  → create SA when requested
  → pre-enable: orgpolicy, iam, drive, iap (as needed) without prompts
  → try keys create
       on managed/classic key-creation org policy:
         resolve ORG; self-grant orgpolicy.policyAdmin if possible (org only)
         set project policy enforce:false + inheritFromParent:false
         retry keys create with backoff; rm empty key files
         if still failing: set org policy enforce:false; retry backoff
         if still failing: external-wait with exact admin commands (last resort)
  → enable drive.googleapis.com if needed
  → Drive share: automate when possible; else external-wait
  → provision Desktop client_id via setup-rclone-drive-client-id.sh
       (IAP / live API — never clientauthconfig; never interactive rclone config create)
  → verify (parse dump in-process; no secret logs)
  → send_agent_result
```

## Steps

### 1. Confirm GCP access, then authenticate gcloud (user — binding)

0. Run **Agent shell bootstrap**.
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

Re-apply **Agent shell bootstrap**. Probe `command -v gcloud` **and**
`${HOME}/google-cloud-sdk/bin/gcloud` (or user-supplied / registry path from
parent handover). If missing after bootstrap → **`failure`** with message that
CLI install belongs to the parent mission registry flow. **Forbidden:**
declaring CLI missing solely because bare `command -v gcloud` failed while the
registry binary exists.

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
2. **Derive a legal SA account id** before any create checkpoint:
   - Start from `inputs.defaultNewServiceAccountId` or a short host-derived
     seed (prefer forms like `centers-dev-sedea-agent`).
   - GCP account ids must be **6–30** characters, lowercase letters, digits,
     hyphens.
   - If the seed is **> 30** chars, **auto-shorten** (truncate with a stable
     readable prefix + `-sedea-agent` or similar) — **no** USER_CHECKPOINT for
     length-only fixes. **Forbidden:** proposing
     `<full-hosting-repo-basename>-sedea-agent` when that string exceeds 30
     (e.g. `centers-development-hosting-repo-sedea-agent` is **invalid**).
   - Key **filename** / `credentialsTargetPath` may stay long; only the
     **account id** is length-capped.
3. USER_CHECKPOINT — select an **existing** SA **or** create with the
   **length-legal** id from step 2 (show the final id in the option label).
4. On **create**: confirm the account id in structured choice before
   `gcloud iam service-accounts create`.
5. **Create JSON key** with self-healing (binding):

#### 4a. Key create + org-policy handler

```bash
# After Agent shell bootstrap; substitute PROJECT, SA_EMAIL, KEY_PATH
# Pre-enable APIs that keys/org-policy may need (non-interactive):
gcloud services enable orgpolicy.googleapis.com iam.googleapis.com \
  --project "$PROJECT" || true

# Remove a prior failed 0-byte key before retry:
if [[ -f "$KEY_PATH" && ! -s "$KEY_PATH" ]]; then rm -f "$KEY_PATH"; fi

gcloud iam service-accounts keys create "$KEY_PATH" \
  --iam-account="$SA_EMAIL" --project="$PROJECT"
```

On **`CUSTOM_ORG_POLICY_VIOLATION`** /
`iam.managed.disableServiceAccountKeyCreation` (or classic
`iam.disableServiceAccountKeyCreation`):

1. Parse **`metadata.customConstraints`** from the error — prefer the
   **managed** constraint id when both appear.
2. Resolve organization id (`gcloud projects get-ancestors` / org list).
3. If the active user can mutate org IAM, grant
   `roles/orgpolicy.policyAdmin` on the **organization** only
   (`gcloud organizations add-iam-policy-binding … --condition=None`).
   **Forbidden:** binding `orgpolicy.policyAdmin` on a **project** (invalid).
4. Set policy **`enforce: false`** for the constraint on the **project**
   (`inheritFromParent: false` when needed) via `gcloud org-policies set-policy`.
5. Retry `keys create` with **backoff** (5–10 attempts, 5–15s sleep). Do **not**
   open a modal on the first post-policy failure — wait for propagation.
6. If project policy is insufficient, set org-level `enforce: false` and retry
   with the same backoff.
7. Before each retry: delete **0-byte** `$KEY_PATH` if present. Success =
   file size &gt; 0 **and** JSON has `client_email` — **never** print
   `private_key`.
8. **Last resort only:** external-wait with the exact admin commands if the
   agent cannot obtain `orgpolicy.policyAdmin` or policy still blocks after
   backoff.

Write the key to **`inputs.credentialsTargetPath`**. Create parent
directories as needed. Do not commit the JSON to git.

### 5. Enable Google Drive API

Re-apply **Agent shell bootstrap**. Run (non-interactive — never answer
enable-API `y/N` prompts):

```bash
gcloud services enable drive.googleapis.com --project "<projectId>"
```

May run while key create is still in org-policy backoff. Record
success/failure. Hard failure → USER_CHECKPOINT retry / abort.

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
2. Run with **Agent shell bootstrap** already applied (example — substitute
   resolved paths; never log secrets):

```bash
bash "<script>" \
  --project-id "<projectId>" \
  --credentials-path "<credentialsTargetPath>" \
  --rclone-remote "<rcloneRemote>"
```

3. OAuth consent must be **Internal** (script sets `orgInternalOnly` when the
   API allows; confirm Internal in Console only if the patch is rejected).
4. Script writes `client_id` / `client_secret` **directly into rclone config**
   (non-interactive `rclone.conf` write — **forbidden** to run interactive
   `rclone config create` in the agent shell) and a local `oauth-client.json`
   under `~/.config/sedea/documentation-management/` (mode 600).
5. **Forbidden:** calling `clientauthconfig.googleapis.com` brands/clients
   APIs (HTTP 404); printing `client_secret`, oauth JSON, `secret:` lines, or
   rclone config dump into chat, `displayMarkdown`, or ops docs; asking the
   user to paste secrets from chat into rclone.
6. Script is bash 3.2-safe (macOS `/bin/bash`). Prefer the shipped script over
   ad-hoc `gcloud components install alpha` (sudo/Python installer often fails
   in agent shells).
7. **Transitional:** IAP OAuth Admin APIs power brand/client create today and
   carry deprecation warnings — if they hard-fail, stop and document Console
   Desktop-client external-wait; do not reintroduce clientauthconfig.

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
