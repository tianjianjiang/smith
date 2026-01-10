---
name: smith-postmortem
description: Incident postmortem methodology and templates. Use when conducting incident postmortems, writing postmortem reports, establishing postmortem processes, or performing post-incident analysis.
---

# Postmortem Standards

<metadata>

- **Scope**: Technical/engineering incident postmortem templates, methodologies, and best practices
- **Load if**: Conducting incident postmortems, writing postmortem reports, establishing postmortem processes, incident response workflows, post-incident analysis
- **Prerequisites**: None (standalone guideline)

</metadata>

<context>

Postmortems are structured reviews after incidents to understand what happened, why it happened, and how to prevent recurrence. Principles: blameless culture (systems, not people), learning focus, timely execution (48-72 hours), actionable outcomes (action items with timelines).

</context>

## Core Principles

<required>

- MUST maintain blameless culture - focus on systems, processes, and contributing factors, not individual fault
- MUST be conducted within 48-72 hours of incident resolution
- MUST include all key participants (incident commander, responders, affected teams)
- MUST result in specific, assigned action items with timelines
- MUST be shared widely within the organization for learning

</required>

<forbidden>

- NEVER assign blame to individuals or teams
- NEVER skip postmortems for "minor" incidents - all incidents provide learning opportunities
- NEVER create action items without owners and timelines
- NEVER conduct postmortems without key participants present

</forbidden>

## Report Structure

Include these sections in order:

### 1. Incident Summary

Include: title, ID, date, duration (ISO 8601 time range), severity (P0/P1/P2), brief description (2-3 sentences), key metrics (downtime, affected users, error rates)

### 2. Impact Assessment

Include: customer impact (users, regions, services), business impact (revenue, SLA violations, reputation), technical impact (degradation, data loss, performance), duration

### 3. Timeline

Include: discovery time/method, key events chronologically (local timezone, ISO 8601), response actions, resolution time, post-resolution verification

```text
YYYY-MM-DDTHH:MM:SS±HH:MM - Alert triggered: [Alert description]
YYYY-MM-DDTHH:MM:SS±HH:MM - On-call engineer paged, investigation started
YYYY-MM-DDTHH:MM:SS±HH:MM - Root cause identified: [Root cause description]
YYYY-MM-DDTHH:MM:SS±HH:MM - Mitigation applied: [Mitigation action]
YYYY-MM-DDTHH:MM:SS±HH:MM - Service restored, monitoring confirmed normal operation
```

### 4. Root Cause Analysis

Include: primary root cause, contributing factors (system design, process gaps, monitoring gaps, documentation gaps, training gaps, environmental factors), analysis methodology (Five Whys, fishbone diagram, timeline analysis), evidence/data

### 5. Resolution Steps

Include: immediate mitigation actions, long-term fixes, verification steps, rollback procedures (if applicable)

### 6. Action Items

Include: ID, description, owner (individual or team), priority (P0/P1/P2 or High/Medium/Low), target completion date, success criteria

**Tracking**: Use structured lists, issue trackers, or project management tools.

### 7. Lessons Learned

Include: what went well, what could be improved, process improvements, tooling improvements, knowledge gaps

### 8. Communication Plan

Include: internal notifications, customer communications (if applicable), status page updates, post-incident review meetings, documentation updates

## Root Cause Analysis Methodologies

### Five Whys Technique

Ask "why" five times to drill down to root cause:

1. Why did the service fail? → [Immediate cause]
2. Why [immediate cause]? → [Underlying cause]
3. Why [underlying cause]? → [Deeper cause]
4. Why wasn't this caught? → [Detection gap]
5. Why [detection gap]? → [Root cause]

### Fishbone Diagram (Ishikawa)

Categorize contributing factors:

- **People**: training, knowledge, communication
- **Process**: procedures, workflows, documentation
- **Technology**: tools, systems, infrastructure
- **Environment**: external factors, dependencies

### Timeline Analysis

Identify: trigger events, cascade failures, response delays, resolution bottlenecks

## Best Practices

### When to Conduct

<required>

- MUST conduct for all P0/P1 incidents (critical/high severity)
- SHOULD conduct for P2 incidents (medium severity) if they reveal systemic issues
- SHOULD conduct for recurring incidents even if individually low severity
- SHOULD conduct for incidents with customer impact

</required>

### Participants

**Required**: Incident commander, primary responders, on-call engineers involved, team leads from affected systems, product/engineering managers (if customer impact)

**Optional**: SRE/DevOps team members, security team (if security-related), customer support (if customer impact), executive stakeholders (for high-severity incidents)

### Timeline for Completion

- **24 hours**: Initial incident summary, impact assessment, basic timeline reconstruction
- **48-72 hours**: Complete postmortem document, root cause analysis, initial action items identified
- **1-2 weeks**: Action items assigned and prioritized, follow-up review meeting scheduled, documentation updates completed

### Sharing and Documentation

<required>

- MUST publish postmortem in accessible location (wiki, documentation system)
- MUST share with all engineering teams
- MUST include in team retrospectives and learning sessions
- MUST update runbooks and documentation based on learnings
- MUST track action items to completion

</required>

### Blameless Language

**Core principle**: Focus on systems, not people. Incidents are system failures; blame prevents learning.

**Guidelines**: Use "we" not "they". Focus on "what" and "why" not "who".

<forbidden>

"[Person] deployed broken code" - assigns blame

</forbidden>

<examples>

"The deployment process allowed code with a connection leak to reach production" - describes system gap

</examples>

## ACTION (Recency Zone)

<required>

**When conducting postmortems:**
1. Schedule within 48-72 hours of incident resolution
2. Include all key participants (incident commander, responders, affected teams)
3. Follow 8-section structure (Summary → Impact → Timeline → Root Cause → Resolution → Action Items → Lessons → Communication)
4. Use Five Whys or fishbone diagram for root cause analysis
5. Assign owners and timelines to all action items
6. Share widely for organizational learning

</required>

<related>

- `@smith-clarity/SKILL.md` - Root cause analysis techniques (Five Whys, fishbone)
- `@smith-validation/SKILL.md` - Hypothesis testing

</related>
