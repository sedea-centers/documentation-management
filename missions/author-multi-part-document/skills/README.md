# author-multi-part-document skills

Spawn contracts for **author-multi-part-document** child lanes. Normative mission
protocol: [`../plan.mdc`](../plan.mdc).

## Relevant Links — post-write registration

Mission Control **Relevant Links** refresh from warm-up, spawn `*Path` / `*Ref`
inputs, terminal `outputs` keys ending in `Path` / `Ref`, and **explicit**
mid-session registration. There is **no** host auto-sniff of Write/StrReplace.
Skills that create or materially edit ops artifacts or the working document
**must** register those paths on the calling lane.

### MCP tool

| Tool | Caller | Purpose |
|------|--------|---------|
| **`mission_control_update_relevant_documents`** | Any agent on **this** lane | Append in-workspace paths to the **calling slot’s** `relevantDocuments` |

**Args (agent-facing):** `paths` — non-empty array of absolute (or workspace-relative)
paths, or `{ path, kind?, label? }` objects. Optional `kind`: `plan` \| `prd` \|
`skill` \| `rule` \| `other`. Host injects lane identity — **forbidden:**
`dispatchId`, `slotId`, `correlationId` in args.

**Delivery:** Stdio MCP acks are transcript-only; the extension host stream mirror
normalizes, dedupes, persists, and patches the panel.

### When to call (binding)

After **Write**, **StrReplace**, or equivalent that **creates or materially edits**
a workspace file the developer should open from Relevant Links, call
**`mission_control_update_relevant_documents`** on the **same turn** (or the next
turn before StreamFinal) with those absolute paths.

| Call | Skip |
|------|------|
| Master plan, part plans, gap reports, review plans under **`operationsDocsDirectory`** or dispatch **`plans/`** | Read-only loads with no write |
| SoT changes follow-up docs and conversation-review evidence under **`operationsDocsDirectory`** | Paths already registered this session with no content change |
| Working document at **`localPath` + `relativeFilePath`** when materially edited | Warm-up manifests; every read path; transient scratch |

**Authored or materially edited only** — do **not** blanket-register warm-up rules
or sibling-dispatch folders.

### Kind hints

| Situation | Prefer |
|-----------|--------|
| Part plan, master plan excerpt artifact, gap report, review plan | `kind: plan` |
| SoT follow-up doc, conversation-review evidence | `kind: other` |
| Working document under documentation folder | `kind: other` (optional **`label`**: part id or basename) |

Optional **`label`** overrides the panel display name when the basename is opaque.

### Relationship to other refresh paths

| Path | Role |
|------|------|
| Warm-up / spawn `*Path` / `*Ref` | Initial seed — still call MCP for **mid-session** creates |
| Terminal `outputs` `*Path` / `*Ref` | Durable child handoff — does **not** replace mid-session register on the active lane |
| Display-metadata MCP | Tab / dispatch chrome only — **not** documents |

### Forbidden

| Pattern | Why |
|---------|-----|
| Register every read path or warm-up manifest | Noise |
| Supply host identity keys in MCP args | Host injects caller slot |
| Prose-only “add this to Relevant Links” without MCP | Panel does not update |
| Display-metadata MCP as a documents substitute | Wrong tool |

Platform authority:
[`.sedea/centers/sedea/rules/9_display-metadata-authority.mdc`](.sedea/centers/sedea/rules/9_display-metadata-authority.mdc)
§ *Relevant Links / documents*.

### Per-skill hooks

| Skill | Register after write |
|-------|---------------------|
| **master-plan** | `masterPlanPath` (`kind: plan`) |
| **part-planner** | `partPlanPath` (`kind: plan`) |
| **author** | working doc + SoT follow-up doc (`kind: other`) |
| **gap-analyzer** | `gapReportPath` (`kind: plan`) |
| **gap-closer** | working doc when materially edited (`kind: other`) |
| **document-reviewer** | `reviewPlanPath` (`kind: plan`) |
| **revision-author** | working doc + SoT follow-up doc (`kind: other`) |
| **content-generator** | working doc when content written (`kind: other`) |

Master plan registration: **`master-plan/SKILL.md`** and **`plan.mdc`** §5b.
