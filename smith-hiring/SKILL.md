---
name: smith-hiring
description: Hands-on IC engineer screening rubric for resumes/CVs — a four-gate framework (named-and-applied mandatory skills, builder-vs-manager test, anti-signals and direction, decisive pre-screen notes), an evidence-quoting one-candidate-per-turn procedure, and submission safety. Use when screening or grading candidate resumes/CVs for an individual-contributor engineering role, judging hands-on builder versus lead/PM/researcher, or evaluating scout/ATS candidate batches.
---

# Hiring: Hands-On IC Screening

<metadata>

- **Scope**: Resume/CV screening to judge hands-on IC fit for one eng role
- **Load if**: Grading resumes/CVs, judging builder vs lead/PM/researcher,
  scout/ATS batch review
- **Prerequisites**: `@smith-clarity/SKILL.md`, `@smith-analysis/SKILL.md`,
  `@smith-validation/SKILL.md`. Role-specific constants (mandatory-skill
  list, named-engine allowlist, grade scale, output register) come from the
  active role brief / project memory. An embedded BizReach instance is below.

</metadata>

## CRITICAL: Read Evidence, Not Keywords (Primacy Zone)

<required>

- Load the role brief / project rubric before grading.
- Read pre-screen notes (scout/ATS tags) FIRST — they carry prior screens.
- Read the FULL resume, not the summary card.
- Identify the current PRIMARY mission and the role verbs first.
- Apply the four gates in order; quote primary-source evidence per call.

</required>

<forbidden>

- Grading from the summary card or a keyword list.
- Accepting an infrastructure-bound claim (e.g. RAG) with no named engine.
- Overweighting impressive secondary / 兼務 work over the primary mission.
- Finalizing or submitting a grade batch without explicit authorization.

</forbidden>

## Gate 1: Mandatory Skills Named and Applied

<required>

- Each required skill must be NAMED and APPLIED in a production system.
- Reject keyword dumps, student-era-only, and classical-only evidence.
- Infrastructure-bound skills require the NAMED underlying engine.

</required>

<context>

- A retrieval/search capability needs a named search or vector engine.
- A generic KV/document store, or an unnamed "we built it", is not credible.
- The authoritative allowlist for a role comes from its brief (see instance).

</context>

## Gate 2: Builder vs Manager (Read Between the Lines)

<context>

- Impressive bullets may be the team's output, led by the candidate.
- Weight the current PRIMARY mission over secondary / 兼務 work.

</context>

<forbidden>

- Treating lead/PM verbs as IC evidence — these cap the grade:
  tech lead, 牽引, 主導, 技術指導(N名), PMO, EM, scrum master,
  product owner, 統括, 企画.
- Counting a domain expert who collaborated WITH engineers as the engineer.

</forbidden>

<required>

- Credit IC signals: 自作, 単独で設計実装, wrote-the-code-myself, with a
  concrete dev environment and the candidate's own metrics.

</required>

## Gate 3: Anti-Signals and Career Direction

<forbidden>

- Treating wrapper-only tooling as depth (e.g. LangChain/LangGraph-only).
- Passing junior tenure unless IC skills are outstanding.
- Ignoring keyword-dump, summary-vs-detail, or timeline mismatch (deduct).
- Passing a level/role mismatch: wants CTO/exec/consultant/generalist/
  research-only, salary above range, or is a founder/CEO.

</forbidden>

## Gate 4: Pre-Screen Notes Are Decisive

<required>

- Read prior human screening notes (scout tags, ATS notes) first.
- Treat "not hands-on", "lacks dev experience", "PM not implementer",
  "research-only NG" as strong corroboration to reject.

</required>

## Procedure

<instructions>

1. Load the role rubric / constants (brief or project memory).
2. Read the pre-screen notes.
3. Read the full resume.
4. Identify the current primary mission and role verbs (IC vs lead).
5. Apply Gates 1 to 4 in order.
6. Present ONE candidate per turn: quote primary-source evidence and
   compare only to the hard criteria — no soft commentary.
7. Propose a grade and WAIT for the human.

</instructions>

## Submission Safety

<forbidden>

- Submitting, finalizing, or auto-clicking a grade in a client-side UI
  without explicit human authorization for that action.
- Advancing or sending a batch without explicit human authorization.

</forbidden>

## Instance: BizReach / cr-support.jp (Stockmark 1156)

<context>

- Role: hands-on AI/NLP engineer (LLM new business); mandatory NLP + RAG.
- Gate-1 named-engine allowlist: Elasticsearch, OpenSearch, Vespa,
  Azure AI Search, pgvector; a dedicated vector DB is weaker; DynamoDB/KV
  or no engine = reject, even if the resume says "RAG構築".
- Grade scale: A 是非会いたい / B 興味があるので会いたい / C 対象外;
  the bar is very selective (mostly C, rare B).
- Output register: quote the JP original, explain in Taiwanese Mandarin,
  one candidate per turn.
- cr-support.jp is an Angular SPA: open with the full URL incl. its hash;
  open a candidate via dispatch-click on its list item; read the resume
  from the H3「職務経歴書 - 和文」container text.
- Timeout alert → browser GO BACK, never refresh (refresh drops grades).
- After reload the list shows only the not-yet-submitted subset.
- Submission: client-side radios; never press 「評価を確定する」 without
  authorization.
- Full instance + session log: project Serena `bizreach_candidate_eval_rubric`
  and `bizreach_1156_grading_session_*`.

</context>

<related>

- `@smith-clarity/SKILL.md` - Cognitive traps when judging people
- `@smith-analysis/SKILL.md` - Decomposing claims into verifiable evidence
- `@smith-validation/SKILL.md` - Hypothesis test: claimed vs demonstrated

</related>

## ACTION (Recency Zone)

<required>

1. Load the role rubric / constants first.
2. Read the pre-screen notes first.
3. Read the full resume, not the summary.
4. Identify the current primary mission and role verbs.
5. Apply Gates 1 to 4 in order.
6. Quote primary-source evidence; compare only to the hard criteria.
7. Present one candidate per turn; propose a grade and WAIT.
8. Never finalize or submit without explicit authorization.

</required>
