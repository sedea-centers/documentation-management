---
name: Document Brainstorm
description: >-
  Optional brainstorming session on a spawned child lane before master planning.
  Scans folder documents and source-of-truth, loops Q&A with the user, and writes
  a brainstorm report under operations docs for downstream master-plan intake.
designation:
  allowed: >-
    Research folder docs and SoT; Q&A with user; write brainstorm report under
    operations docs; report completion gate
  forbidden: >-
    Writes under source-of-truth/; master-plan or part-lane spawn from this lane;
    dispatch resolution
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

Spawned **document-brainstorm** for **author-multi-part-document** §2.5. Loop
with the **user** until intent is clear enough for master planning; write a
structured report the Squad Leader auto-chains to **master-plan**.

**This skill never** emits **`mission_control_spawn_agent`** for **`master-plan`**
or part lanes — the **Squad Leader** auto-spawns **master-plan** after terminal
approval per **`plan.mdc`** §2.5.

## Agent messaging (MCP)

| Action | MCP tool |
|--------|----------|
| **This** spawned lane terminal | **`mission_control_send_agent_result`** |

**Forbidden** in MCP args: host-resolved identity keys (`correlationId`,
`dispatchId`, `slotId`, …).

## Checkpoint turn UX (skill-local)

Under **`trustLevel: checkpoint`**, auto-advance happy-path steps; structured
choice only at **USER_CHECKPOINT** markers, external-wait surfaces, or
exceptions.

| Step | Checkpoint behavior | Gate |
|------|---------------------|------|
| **1–3** — Open session / scan / Q&A loop | Auto-advance until report-worthy material | exception: missing required inputs → `partial` |
| **4** — Synthesize + write report | Auto-advance on successful write | exception: write failure → `partial` |
| **5** — Present for completion | **Gate** — first user-pick gate on this lane | Report completion gate (below) |
| **6–7** — Approve / abandon terminal | Auto-advance refocus + MCP result | — |
| **Continue brainstorming** at step **5** | Auto-advance back to steps **1–3** | no gate until step **5** re-presents |

### Report completion gate (binding)

USER_CHECKPOINT — continue brainstorming, approve report, revise report, or
abandon dispatch on this lane.

**Spawned lane — MCP structured choice (binding):** Call
**`mission_control_present_structured_choice`** (recap in **`displayMarkdown`**;
options in **`askQuestion`**) per rule **2**.

| Option id | Label |
|-----------|--------|
| `continue-brainstorming` | Continue brainstorming — explore more sources or questions |
| `approve-report` | Approve report — send to Squad Leader for master planning |
| `revise-research` | Revise report — update sections on this lane |
| `abandon-dispatch` | Abandon dispatch — direction not viable |
| `more-details` | More details for option _ |
| `have-question` | I have a question |
| `introspect-incident` | Introspect and report an incident |
| `other` | Other |

**Forbidden at step 5:** **`approve-report`** as the **first** listed option;
prose-only recap; ending without structured choice on spawned lanes.

## Procedure

1. **Open the session** — Restate `brainstormTopic`, `brainstormPrompt`, and
   `openingSeeds` when present. Confirm folder binding (`localPath`, optional
   `folderSlug`). Ask what the user wants to explore.

2. **Scan and answer** — Read documents under `localPath` and consult
   `<localPath>/source-of-truth/` per
   [rule 20](../../../../rules/20_source-of-truth.mdc). **Do not** treat
   **`CHANGELOG.md`** as authoritative SoT unless the user explicitly names it.
   Answer user questions from scanned material; note paths in working notes.

3. **Loop** — Continue Q&A until the user confirms readiness for master planning
   (no fixed turn count). Update working notes each turn.

4. **Write report** — Save under `operationsDocsDirectory` as
   `brainstorm_<slug>_<8hex>.brainstorm-report.md` (kebab slug from title;
   regenerate hex on collision once). Use **Report file shape** below.

   - **Relevant Links (post-write):** Call
     **`mission_control_update_relevant_documents`** with the absolute report
     path (`kind: other`) on this lane — same turn preferred.

5. **Present for completion** — Recap report path and Handoff summary excerpt in
   **`displayMarkdown`**. Open [Report completion gate](#report-completion-gate-binding)
   via **`mission_control_present_structured_choice`** — same turn.

6. **On Approve report** — Set `userApprovedReport: true`, `abandonMission:
   false`, `continuationStatus: "terminal"`, `continuationOwner: "squad-leader"`.
   Populate **`downstreamHandoffSummary`**, **`downstreamSpawnTarget:
   master-plan`**, **`objectives[]`**, **`documentsToChange[]`** from the report.
   Call **`mission_control_refocus_parent_lane`** immediately before MCP result.

7. **On Abandon dispatch** — Set `userApprovedReport: false`, `abandonMission:
   true`, terminal outputs; refocus parent + MCP result with optional
   `abandonReason`.

**On Continue brainstorming** — Resume steps **1–3**; return to step **5** when
the report is updated.

**On Revise research** — Update report sections on this lane; return to step **5**.

## Report file shape (template)

```markdown
# <Title>

**Invoker mission:** `author-multi-part-document`
**Downstream target:** `master-plan`
**Folder:** `<folderSlug or localPath>`

## 1. Research question

<What the user wants to accomplish?>

## 2. User objectives

<Derived, numbered objectives>

## 3. Findings

<Key observations from folder docs and SoT>

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

Emit **`mission_control_send_agent_result`** with **`status`**, **`summary`**,
optional **`outputs`** / **`errors`** (`[]` when none).

Required `outputs` fields:

- `outputs.brainstormReportPath`
- `outputs.brainstormReportRef` — `@`-prefixed path for handoff
- `outputs.reportTitle`
- `outputs.operationsDocsDirectory`
- `outputs.invokerMissionSlug`
- `outputs.objectives` — array of objective strings
- `outputs.documentsToChange` — array of `{ path, rationale }` objects
- `outputs.userApprovedReport` — `true` only on **Approve report**
- `outputs.abandonMission` — `true` only on **Abandon dispatch**
- `outputs.abandonReason` — optional when abandoning
- `outputs.downstreamSpawnTarget` — `master-plan` when approved
- `outputs.downstreamHandoffSummary` — required when `userApprovedReport: true`
- `outputs.continuationOwner`
- `outputs.continuationStatus`

**Forbidden:** `userApprovedReport: true` with empty `downstreamHandoffSummary`.
**Forbidden:** spawning **master-plan** from this lane.

Stop after the MCP result call.
