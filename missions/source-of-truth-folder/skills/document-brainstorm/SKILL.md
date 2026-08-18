---
name: Document Brainstorm
description: >-
  Optional analysis-first brainstorming session on a spawned child lane before
  SoT change planning. Tracks user requests, scans folder documents and
  source-of-truth, optionally looks up prior authoring missions for SoT-worthy
  facts, maintains an interim request log, then writes a final brainstorm report
  under operations docs when the user approves.
designation:
  allowed: >-
    Analysis-first research (folder doc reads, SoT consultation, prior
    authoring-mission lookup in ops docs, structure/outline analysis, cross-doc
    grep/counts, web search); request-ledger tracking; interim request-log writes
    under operations docs; final report write on approval; dual structured-choice
    gates
  forbidden: >-
    Skip substantive analysis to synthesize conclusions; write final report while any
    request is open; writes under source-of-truth/; gather/plan lane spawn from this
    lane; dispatch resolution
inputs:
  invokerMissionSlug:
    type: string
    description: Mission that spawned this lane (source-of-truth-folder).
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
  - .sedea/centers/documentation-management/missions/source-of-truth-folder/plan.mdc
  - .sedea/centers/documentation-management/rules/20_source-of-truth.mdc
  - .sedea/centers/sedea/rules/2_ask-question-instructions.mdc
---

# Document brainstorm

Spawned **document-brainstorm** for **source-of-truth-folder** §2.5. Runs an
**analysis-first** session with the **user** until SoT change planning is
well-grounded; writes a structured report the Squad Leader auto-chains to §4/§5.

**This skill never** writes under **`source-of-truth/`** or emits
**`mission_control_spawn_agent`** for gather/plan lanes — the **Squad Leader**
continues §4/§5 after terminal approval per **`plan.mdc`** §2.5.

## Agent messaging (MCP)

| Action | MCP tool |
|--------|----------|
| **This** spawned lane terminal | **`mission_control_send_agent_result`** |

**Forbidden** in MCP args: host-resolved identity keys (`correlationId`,
`dispatchId`, `slotId`, …).

## When this skill applies

**Actor:** **Document brainstorm agent** — spawned child lane only.

**Act when** the invoker selected **`brainstorm-first`** at §3 and supplied
**`invokerMissionSlug`**, **`operationsDocsDirectory`**, and **`localPath`**.

If required spawn **`inputs`** are missing, stop with `status: "partial"`,
`outputs.missingFields` populated — do not write files.

## Analysis toolkit (binding)

| Kind | Examples |
|------|----------|
| **Folder docs** | Read documents under `localPath`; compare structure, headings, and coverage |
| **Source of truth** | Consult `<localPath>/source-of-truth/` per [rule 20](../../../../rules/20_source-of-truth.mdc) |
| **Prior authoring missions** | When user opts in via **`lookup-prior-authoring`**, search **`operationsDocsDirectory`** and dispatch **`plans/`** for artifacts from **author-simple-document** and **author-multi-part-document** (deviation reports, SoT follow-ups, brainstorm reports, master/part plans) scoped to same `folderSlug` / `localPath` |
| **Structure analysis** | Outline gaps, topic boundaries, cross-references between docs and SoT |
| **Cross-doc search** | Grep, count, or summarize patterns across the documentation folder |
| **Web** | Search for external standards, terminology, or reference material |
| **Operations docs** | Read prior ops artifacts under `operationsDocsDirectory` when relevant |

**Do not** treat **`CHANGELOG.md`** as authoritative SoT unless the user
explicitly names it.

**Forbidden:** jump to synthesis or final report write **without** substantive
analysis when open requests require it; auto-write SoT from prior-authoring lookup.

## Prior authoring mission lookup (binding)

At the **analysis gate**, offer **`lookup-prior-authoring`** — *Look up prior
authoring missions for SoT-worthy facts* — when not already completed this session.

**When selected (or user affirms in chat):**

1. Set `priorAuthoringLookupRequested: true` on the session ledger.
2. Search ops docs and dispatch plan folders for **author-simple-document** and
   **author-multi-part-document** artifacts tied to the same registered folder
   (`folderSlug`, `localPath`, or explicit path references).
3. Summarize candidate **facts**, **topics**, and **claims** that could enrich
   SoT — cite source paths; **forbidden:** write under **`source-of-truth/`**.
4. Record findings in the request ledger and interim log; include in final report
   § *Prior authoring sources consulted*.

## Request ledger (binding)

| Field | Rule |
|-------|------|
| **Request item** | One row: request text + **`open`** or **`done`** + outcome note |
| **Seed** | Step **1** seeds from **`brainstormPrompt`**, **`openingSeeds`**, intake chat |
| **Append** | New user messages on **`continue-analyzing`** append rows as **`open`** |
| **Complete** | Mark **`done`** only after analysis ran and outcome is recorded |
| **Gate rule** | **Forbidden:** offer **`approve-write-report`** while any request is **`open`** |

## Checkpoint turn UX (skill-local)

Under **`trustLevel: checkpoint`**, auto-advance scripted happy-path steps;
structured choice only at **USER_CHECKPOINT** markers, external-wait surfaces,
or exceptions.

### Analysis gate (binding)

USER_CHECKPOINT — continue analyzing, look up prior authoring missions, approve
final report write, or abandon dispatch on this lane. defaultOptionId: continue-analyzing

| Option id | Label |
|-----------|--------|
| `continue-analyzing` | Continue analyzing — run more analysis or fulfill open requests |
| `lookup-prior-authoring` | Look up prior authoring missions for SoT-worthy facts |
| `approve-write-report` | Approve — all requests done, write final report |
| `abandon-dispatch` | Abandon dispatch — direction not viable |
| `more-details` | More details for option _ |

**Forbidden:** listing **`approve-write-report`** first or as **`defaultOptionId`**
while any request is **`open`**; ending without structured choice on spawned lanes.

### Post-write revision gate (binding)

USER_CHECKPOINT — revise report, approve and send to Squad Leader, or abandon
dispatch on this lane. defaultOptionId: revise-report

| Option id | Label |
|-----------|--------|
| `revise-report` | Revise report — update conclusions before handoff |
| `approve-report-send` | Approve report — send to Squad Leader for SoT change planning |
| `abandon-dispatch` | Abandon dispatch — direction not viable |
| `more-details` | More details for option _ |

## Brainstorm session (steps)

1. **Intake anchor** — Restate topic/prompt/seeds; confirm folder binding; seed
   request ledger. Auto-advance to step **2**.

2. **Analysis loop** — Fulfill **`open`** requests per **Analysis toolkit**.
   Update interim request-log file. Auto-advance to step **3** when ready.

3. **Analysis gate** — Recap intake, ledger, proposed next steps; open structured
   choice — **gate**.

4. **On Continue analyzing** — Append new requests; return to step **2**.

5. **On Lookup prior authoring** — Run **Prior authoring mission lookup**; return
   to step **2** or re-present step **3**.

6. **On Approve write report** — Verify all requests **`done`**; write final report
   under `operationsDocsDirectory` as
   `brainstorm_<slug>_<8hex>.brainstorm-report.md`. Register via
   **`mission_control_update_relevant_documents`**. Auto-advance to step **7**.

7. **Post-write revision gate** — Recap report path; open structured choice — **gate**.

8. **On Approve report send** — Set `userApprovedReport: true`,
   `downstreamSpawnTarget: sot-change-plan`, populate **`sotTopics[]`**,
   **`recommendedSotPaths[]`**, **`downstreamHandoffSummary`**. Call
   **`mission_control_refocus_parent_lane`** then terminal MCP result.

9. **On Abandon dispatch** — Set `abandonMission: true`; refocus parent; terminal
   MCP result.

## Report file shape (template)

```markdown
# <Title>

**Invoker mission:** `source-of-truth-folder`
**Downstream target:** `sot-change-plan`
**Folder:** `<folderSlug or localPath>`
**Request log:** `<path to brainstorm-requests.md>`

## 1. Research question

<What SoT refresh or author goal?>

## 2. SoT objectives

<Derived, numbered objectives>

## 3. Findings

<Key observations from folder docs, SoT, and analysis>

## 4. Recommended SoT paths

| Path under source-of-truth/ | Rationale |
|-----------------------------|-----------|
| … | … |

## 5. Prior authoring sources consulted

<Paths and summaries when lookup ran — empty when skipped>

## 6. Handoff summary

<Concise block for Squad Leader §5 SoT change plan draft>

## Sources consulted

<Paths under localPath, source-of-truth/, and ops docs>
```

## Completion (spawned)

Required `outputs` fields:

- `outputs.brainstormReportPath`
- `outputs.brainstormReportRef`
- `outputs.brainstormRequestsPath` / `outputs.brainstormRequestsRef` when written
- `outputs.reportTitle`
- `outputs.operationsDocsDirectory`
- `outputs.invokerMissionSlug`
- `outputs.sotTopics` — array of topic strings
- `outputs.recommendedSotPaths` — array of `{ path, rationale }` under `source-of-truth/`
- `outputs.priorAuthoringLookupRequested` — boolean
- `outputs.priorAuthoringFindingsSummary` — string when lookup ran
- `outputs.userApprovedReport`
- `outputs.abandonMission`
- `outputs.downstreamSpawnTarget` — `sot-change-plan` when approved
- `outputs.downstreamHandoffSummary` — required when `userApprovedReport: true`
- `outputs.continuationOwner` / `outputs.continuationStatus`

**Forbidden:** `userApprovedReport: true` with empty `downstreamHandoffSummary`.
**Forbidden:** writing under **`source-of-truth/`** from this lane.

Stop after the MCP result call.

## Out of scope

- Does **not** draft or approve SoT change plans — Squad Leader §5 owns that.
- Does **not** call **`mission_control_propose_dispatch_resolution`**.
