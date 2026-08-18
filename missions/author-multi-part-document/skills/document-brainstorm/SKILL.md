---
name: Document Brainstorm
description: >-
  Optional analysis-first brainstorming session on a spawned child lane before
  master planning. Tracks user requests (questions and tasks), scans folder
  documents and source-of-truth, maintains an interim request log, then writes
  a final brainstorm report under operations docs when the user approves.
designation:
  allowed: >-
    Analysis-first research (folder doc reads, SoT consultation, structure/outline
    analysis, cross-doc grep/counts, web search); request-ledger tracking; interim
    request-log writes under operations docs; final report write on approval; dual
    structured-choice gates
  forbidden: >-
    Skip substantive analysis to synthesize conclusions; write final report while any
    request is open; writes under source-of-truth/; master-plan or part-lane spawn
    from this lane; dispatch resolution
inputs:
  invokerMissionSlug:
    type: string
    description: Mission that spawned this lane (author-multi-part-document).
    required: true
  operationsDocsDirectory:
    type: string
    description: Absolute ops docs write root from lane identity or spawn inputs.
    required: true
  localPath:
    type: string
    description: Absolute local root for the registered documentation folder.
    required: true
  folderSlug:
    type: string
    description: Registered documentation folder slug from §2.
    required: false
  brainstormTopic:
    type: string
    description: Optional short title for the session and report filename.
    required: false
  brainstormPrompt:
    type: string
    description: Optional opening question or scope hint from Squad Leader intake.
    required: false
  openingSeeds:
    type: string
    description: Optional remainder text from the dispatch opening message.
    required: false
warmUpRules:
  - .sedea/centers/documentation-management/missions/author-multi-part-document/plan.mdc
  - .sedea/centers/documentation-management/rules/20_source-of-truth.mdc
  - .sedea/centers/sedea/rules/2_ask-question-instructions.mdc
---

# Document brainstorm

Spawned **document-brainstorm** for **author-multi-part-document** §2.5. Runs an
**analysis-first** session with the **user** until intent is clear enough for
master planning; writes a structured report the Squad Leader auto-chains to
**master-plan**.

**This skill never** emits **`mission_control_spawn_agent`** for **`master-plan`**
or part lanes — the **Squad Leader** auto-spawns **master-plan** after terminal
approval per **`plan.mdc`** §2.5.

## Agent messaging (MCP)

| Action | MCP tool |
|--------|----------|
| **This** spawned lane terminal | **`mission_control_send_agent_result`** |

**Forbidden** in MCP args: host-resolved identity keys (`correlationId`,
`dispatchId`, `slotId`, …).

## When this skill applies

**Actor:** **Document brainstorm agent** — spawned child lane only.

**Act when** the invoker selected **`brainstorm-first`** at mission intake and
supplied **`invokerMissionSlug`**, **`operationsDocsDirectory`**, and
**`localPath`**.

If required spawn **`inputs`** are missing, stop with `status: "partial"`,
`outputs.missingFields` populated — do not write files.

## Analysis toolkit (binding)

The lane exists to **perform analysis** before synthesizing conclusions. Use
tools as the research question requires:

| Kind | Examples |
|------|----------|
| **Folder docs** | Read documents under `localPath`; compare structure, headings, and coverage |
| **Source of truth** | Consult `<localPath>/source-of-truth/` per [rule 20](../../../../rules/20_source-of-truth.mdc) |
| **Structure analysis** | Outline gaps, part boundaries, cross-references between docs |
| **Cross-doc search** | Grep, count, or summarize patterns across the documentation folder |
| **Web** | Search for external standards, terminology, or reference material |
| **Operations docs** | Read prior ops artifacts under `operationsDocsDirectory` when relevant |

**Do not** treat **`CHANGELOG.md`** as authoritative SoT unless the user
explicitly names it.

**Forbidden:** jump to synthesis, recommendations, or final report write
**without** running substantive analysis when the intake task or open requests
require it. **Forbidden:** treat chat-only speculation as fulfillment of a
task-form request that requires tool execution.

## Request ledger (binding)

Track every user **request** for the session — not only question-form phrasing.

| Field | Rule |
|-------|------|
| **Request item** | One row: request text + **`open`** or **`done`** + outcome note (path, count, summary) |
| **Seed** | Step **1** seeds the ledger from **`brainstormPrompt`**, **`openingSeeds`**, and intake chat |
| **Append** | New user messages on **`continue-analyzing`** or free-form chat append new rows as **`open`** |
| **Complete** | Mark **`done`** only after analysis ran and the outcome note is recorded |
| **Gate rule** | **Forbidden:** offer **`approve-write-report`** while any request is **`open`** |

## Checkpoint turn UX (skill-local)

Under **`trustLevel: checkpoint`**, auto-advance scripted happy-path steps;
structured choice only at **USER_CHECKPOINT** markers, external-wait surfaces,
or exceptions. **No cross-skill inheritance** — gate defaults here apply only to
**`document-brainstorm`**; the invoking mission documents its own Squad Leader
§2.5 **#external-wait** and failure/partial USER_CHECKPOINT gates — see
**`plan.mdc`** §2.5.

Marker syntax: [`.sedea/centers/sedea/docs/user-checkpoint-marker-syntax.md`](.sedea/centers/sedea/docs/user-checkpoint-marker-syntax.md).

### Developer input vs external-wait (Checkpoint)

Under Checkpoint trust, **happy-path protocol steps auto-advance without a
turn-end modal**. Emit **`mission_control_present_structured_choice`** or
**AskQuestion** only at **USER_CHECKPOINT** markers in this skill, **implicit
external-wait** surfaces, or **exception** paths.

**Developer-input** gates (**analysis gate**, **post-write revision gate**)
**must** close the turn with structured choice — **Forbidden:** prose-only idle
handoff (for example tell-me-when / review-and-reply / pick-in-chat substitutes
for the modal).

**Active analysis (steps 1–2)** is **not** external-wait — the agent **Acts**
(tools, ledger updates, interim file writes) until step **3** presents the
analysis gate.

| Step | Checkpoint behavior | Gate |
|------|---------------------|------|
| **1** — Intake anchor | Auto-advance — seed request ledger; confirm folder binding | exception: missing required inputs → `partial` |
| **2** — Analysis loop | Auto-advance — execute open requests; update interim file | exception: unrecoverable tool failure → note in ledger, stay `open` |
| **3** — Analysis gate | **Gate** — first user-pick gate | [Analysis gate](#analysis-gate-binding) |
| **4** — On continue-analyzing | Auto-advance back to step **2** | no gate until step **3** re-presents |
| **5** — On approve-write-report | Auto-advance — verify all requests **`done`**; write final report | exception: open requests remain → re-present step **3** |
| **6** — Post-write revision gate | **Gate** | [Post-write revision gate](#post-write-revision-gate-binding) |
| **7** — On revise-report | Auto-advance — edit report; re-present step **6** | — |
| **8** — On approve-report-send | Auto-advance to refocus + terminal MCP result | — |
| **9** — On Abandon dispatch | Auto-advance to refocus + terminal MCP result | — |

### Analysis gate (binding)

USER_CHECKPOINT — continue analyzing, approve final report write, or abandon
dispatch on this lane. defaultOptionId: continue-analyzing

**Spawned lane — MCP structured choice (binding):** Call
**`mission_control_present_structured_choice`** (recap in **`displayMarkdown`**;
options in **`askQuestion`**) per rule **2**.

Recap **must** include: intake task anchor, folder binding, request ledger table
(open/done), and **proposed next steps** for open requests tied to the intake
task.

| Option id | Label |
|-----------|--------|
| `continue-analyzing` | Continue analyzing — run more analysis or fulfill open requests |
| `approve-write-report` | Approve — all requests done, write final report |
| `abandon-dispatch` | Abandon dispatch — direction not viable |
| `more-details` | More details for option _ |

**Forbidden at analysis gate:** listing **`approve-write-report`** as the first
mission-specific option or using **`defaultOptionId: approve-write-report`**;
offering **`approve-write-report`** while any request is **`open`**; prose-only
recap with bullet menus; ending without structured choice on spawned lanes.

### Post-write revision gate (binding)

USER_CHECKPOINT — revise report, approve and send to Squad Leader, or abandon
dispatch on this lane. defaultOptionId: revise-report

| Option id | Label |
|-----------|--------|
| `revise-report` | Revise report — update conclusions before handoff |
| `approve-report-send` | Approve report — send to Squad Leader for master planning |
| `abandon-dispatch` | Abandon dispatch — direction not viable |
| `more-details` | More details for option _ |

**Forbidden at post-write gate:** listing **`approve-report-send`** as the first
mission-specific option or using **`defaultOptionId: approve-report-send`**;
skipping this gate after the first final report write; ending without structured
choice on spawned lanes.

## Brainstorm session (steps)

1. **Intake anchor** — Restate `brainstormTopic`, `brainstormPrompt`, and
   `openingSeeds` when present. Confirm folder binding (`localPath`, optional
   `folderSlug`). State the **intake task** this session serves. Seed the
   **request ledger** from intake text and any user messages so far (questions
   **or** tasks).

   - **Next-step resolution:** Auto-advance to step **2**.

2. **Analysis loop** — For each **`open`** request, run analysis per **Analysis
   toolkit**. Record outcomes in the ledger; mark **`done`** when fulfilled.
   Update the interim request-log file (see **Interim request log shape**).
   Propose **next steps** mentally for step **3** recap.

   - **Relevant Links (post-write):** After a successful create or material
     revise write of the interim file, call MCP
     **`mission_control_update_relevant_documents`** with the absolute path
     (`kind: other`) on this lane — same turn preferred. **Skip** when already
     registered this session with no content change.

   - **Next-step resolution:** Auto-advance to step **3** when at least one
     analysis pass completed or all seeded requests are addressed — no gate on
     this step.

3. **Analysis gate** — Recap intake task, folder binding, request ledger, and
   **proposed next steps** in **`displayMarkdown`**. Open [Analysis
   gate](#analysis-gate-binding) via **`mission_control_present_structured_choice`**
   or **AskQuestion** — **same turn**, not prose-only.

   - **Next-step resolution:** **Gate** — user pick required before steps **4–9**.

4. **On Continue analyzing** — Append any new user requests from chat to the
   ledger as **`open`**. Return to step **2**.

   - **Next-step resolution:** Auto-advance through analysis work — no gate
     until step **3** re-presents.

5. **On Approve write report** — Verify every request is **`done`**. If any
   remain **`open`**, re-present step **3** with explanation — **do not** write
   the final report. When all are **`done`**, synthesize conclusions and write
   the final report under `operationsDocsDirectory` as
   `brainstorm_<slug>_<8hex>.brainstorm-report.md` (kebab slug from title;
   regenerate hex on collision once). Use **Report file shape** below.

   - **Relevant Links (post-write):** After a successful final report write,
     call MCP **`mission_control_update_relevant_documents`** with the absolute
     report path (`kind: other`).

   - **Next-step resolution:** Auto-advance to step **6**.

6. **Post-write revision gate** — Recap report path and §6 Handoff summary
   excerpt in **`displayMarkdown`**. Open [Post-write revision
   gate](#post-write-revision-gate-binding) — **same turn**, not prose-only.

   - **Next-step resolution:** **Gate** — user pick required before terminal
     handoff.

7. **On Revise report** — Edit the final report per user feedback; return to
   step **6**.

   - **Next-step resolution:** Auto-advance through edits — gate at step **6**
     after update.

8. **On Approve report send** — Set `userApprovedReport: true`, `abandonMission:
   false`, `continuationStatus: "terminal"`, `continuationOwner: "squad-leader"`.
   Populate **`downstreamHandoffSummary`**, **`downstreamSpawnTarget:
   master-plan`**, **`objectives[]`**, **`documentsToChange[]`** from the report.
   Call **`mission_control_refocus_parent_lane`** immediately before MCP result.

   - **Next-step resolution:** Auto-advance to terminal MCP result.

9. **On Abandon dispatch** (either gate) — Set `userApprovedReport: false`,
   `abandonMission: true`, `continuationStatus: "terminal"`,
   `continuationOwner: "squad-leader"`. Call
   **`mission_control_refocus_parent_lane`** then MCP result with optional
   `abandonReason`.

   - **Next-step resolution:** Auto-advance to terminal MCP result.

## Interim request log shape (template)

Save under `operationsDocsDirectory` as
`brainstorm_<slug>_<8hex>.brainstorm-requests.md` (same slug/hex family as the
final report when possible). **Request log only — no conclusions.**

```markdown
# Request log — <title>

**Intake task:** <anchor from brainstormPrompt / openingSeeds / intake chat>
**Invoker mission:** `author-multi-part-document`
**Folder:** `<folderSlug or localPath>`

| # | Request | Status | Outcome |
|---|---------|--------|---------|
| 1 | compare part 2 outline to SoT objectives | done | 3 gaps noted; paths in Sources |
| 2 | count how many docs lack a summary section | open | — |

## Sources consulted

<Paths under localPath, source-of-truth/, and ops docs>
```

## Report file shape (template)

Written only on step **5** after all requests are **`done`** and the user picks
**`approve-write-report`**, then revised through steps **6–7** as needed.

```markdown
# <Title>

**Invoker mission:** `author-multi-part-document`
**Downstream target:** `master-plan`
**Folder:** `<folderSlug or localPath>`
**Request log:** `<path to brainstorm-requests.md>`

## 1. Research question

<What the user wants to accomplish?>

## 2. User objectives

<Derived, numbered objectives>

## 3. Findings

<Key observations from folder docs and SoT, grounded in request ledger outcomes>

## 4. Recommended document changes

<What should change and why>

## 5. Documents to change

| Path | Rationale |
|------|-----------|
| … | … |

## 6. Handoff summary

<Concise block for master-plan spawn initiatingPrompt / structureOutline>

## Sources consulted

<Paths under localPath and source-of-truth/>
```

## Completion (spawned)

### MCP result preflight (`mission_control_send_agent_result`)

| Step | Check |
|------|--------|
| R1 | Call **`mission_control_send_agent_result`** with **`status`**, **`summary`**, optional **`outputs`** / **`errors`** |
| R2 | **Forbidden args absent** — no **`correlationId`**, **`dispatchId`**, **`slotId`**, or other host-resolved keys |
| R3 | Populate **`outputs`** from the required field list below |
| R4 | Re-emit updated MCP result after user-requested follow-up on this lane (same spawn session) |
| R5 | **`mission_control_refocus_parent_lane`** — **Required** on Approve / Abandon terminal per steps **8–9**; **forbidden** while **`continuationStatus: active`** |

**Message order on terminal turns:** optional recap →
**`mission_control_present_structured_choice`** (when a gate is open) →
**`mission_control_refocus_parent_lane`** (when required) →
**`mission_control_send_agent_result`** (**last**).

Required `outputs` fields:

- `outputs.brainstormReportPath`
- `outputs.brainstormReportRef` — `@`-prefixed path for handoff
- `outputs.brainstormRequestsPath` — absolute path to interim request log when written
- `outputs.brainstormRequestsRef` — `@`-prefixed path to interim request log when written
- `outputs.reportTitle`
- `outputs.operationsDocsDirectory`
- `outputs.invokerMissionSlug`
- `outputs.objectives` — array of objective strings
- `outputs.documentsToChange` — array of `{ path, rationale }` objects
- `outputs.userApprovedReport` — `true` only on **Approve report send**
- `outputs.abandonMission` — `true` only on **Abandon dispatch**
- `outputs.abandonReason` — optional when abandoning
- `outputs.downstreamSpawnTarget` — `master-plan` when approved
- `outputs.downstreamHandoffSummary` — required when `userApprovedReport: true`
- `outputs.continuationOwner`
- `outputs.continuationStatus`
- `outputs.missingFields`
- `outputs.remainingTasks`

**Continuation:**

- During active analysis before final report approval: `continuationOwner:
  "document-brainstorm-agent"`, `continuationStatus: "active"`,
  `userApprovedReport: false`, `abandonMission: false`.
- On terminal approve or abandon: `continuationOwner: "squad-leader"`,
  `continuationStatus: "terminal"`.

**Forbidden:** `userApprovedReport: true` with empty `downstreamHandoffSummary`.
**Forbidden:** spawning **master-plan** from this lane.

Stop after the MCP result call.

## Out of scope

- Does **not** create master plans or part plans — **master-plan** owns those
  artifacts.
- Does **not** call MCP **`mission_control_propose_dispatch_resolution`** —
  Squad Leader proposes **`abandoned`** when `abandonMission: true`.
