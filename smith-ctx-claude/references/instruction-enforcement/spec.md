# Instruction enforcement — Spec (the contract)

> The *why* lives in `intent.md`. This file states what must hold; how it is
> made to hold belongs in `plan.md`. "The agent" is the assistant working
> under this repository's instructions; "the owner" is the person it works
> for.

## §no-open-item-at-turn-end

**EARS (Easy Approach to Requirements Syntax)**: If the last message of a
turn names part of the request as unverified, not checked or not traced, or
asks the owner whether the agent should check it, and closing that part
needs nothing that only the owner can give, then the agent shall close it
before the turn ends.

"Only the owner can give" means a yes to commit, push, delete or send words
to another person, a decision on scope, or access the agent does not have.

**GWT (Given-When-Then)**:
- Given a request whose answer depends on where a configuration value comes
  from, and the file that sets the value is readable by the agent
- When the agent's draft of its last message says "I did not trace where the
  value comes from" or "shall I check it now or mark it unverified?"
- Then the turn does not end on that message; the agent traces the value,
  and the last message states where it comes from, with the file and line

## §owner-item-carries-its-context

**EARS**: When a turn ends with an item that only the owner can close, the
agent shall have finished every part of the request that does not depend on
the owner's answer, and the last message shall state, for that item: what it
is, where it lives, how many things it covers, what the agent already did
about it, and the one thing needed from the owner. A term, code or name the
owner has not seen is defined where it is first used.

**GWT**:
- Given a request to fix a failing check and ship the fix, where the fix is
  made and verified and shipping needs the owner's yes
- When the turn ends
- Then the last message names the commit to be pushed, its branch, the one
  file it changes, the check that now passes, and asks for the yes to push;
  nothing else in the request is left undone
- Given the same request, and the agent's draft of its last message asks
  "how should I handle the 12 stale cases?" without having said what a
  stale case is or where the 12 are
- When the turn ends
- Then the last message says what makes a case stale, lists where the 12
  are, and says what each choice would do to them

## §change-reaches-every-reference

**EARS**: When the agent changes a name, a path, a command, a number, a
rule or a behaviour, the agent shall find every place in scope that states
or depends on the old form, and before the turn ends each such place shall
either agree with the change or be named in the last message with the
reason it was left.

"In scope" is the repository being changed, plus the sibling profiles and
project-local copies that `intent.md` lists when the changed thing exists in
them.

**GWT**:
- Given a script whose option is renamed, and the old option name appears
  in the script's test, in one skill file and in one reference document
- When the agent renames the option and the turn ends
- Then the test, the skill file and the reference document use the new
  name, and a search of the repository for the old name finds nothing
- Given a setting changed in the personal profile that the two other
  profiles also hold
- When the turn ends
- Then the last message shows the exact difference each other profile would
  receive and says that each waits for the owner's yes

## §covering-skill-loaded-before-acting

**EARS**: When a task falls within what an available skill covers, the
agent shall load that skill before the first action of the task, shall say
in the same message which skill it loaded and why, and shall act as the
skill directs; the owner shall not have to name the skill.

A skill "covers" a task when the skill's own description or its stated
load condition matches what the task is. Recalling a skill's content from
memory, or reading its file without loading it, does not count as loading.

**GWT**:
- Given a request to stress-test a plan, and an available skill whose
  description says it stress-tests a plan
- When the agent takes its first action on the request
- Then that skill is already loaded in this turn, the message names it with
  the reason, and the owner's request did not contain the skill's name
- Given a request to commit a change, and an available skill that governs
  commits and requires a signed commit with an attribution trailer
- When the commit is made
- Then the skill was loaded before the commit command ran, and the commit
  is signed and carries the trailer
- Given a task that no available skill covers
- When the agent acts
- Then no skill is loaded for it and none is claimed

## §skill-file-holds-no-point-in-time-content

**EARS**: A skill file (`SKILL.md`) shall contain no calendar date, no
status of work, no account of an incident or of how a rule came about, and
no pull-request, issue, commit or ticket reference. If the agent writes or
edits a skill file, then the file shall satisfy this when the turn ends.

A skill file may name the source of a rule by its URL or file path. The date
a source was retrieved, the version of a tool that was checked, and the
history behind a rule belong in a document under the skill's `references/`
folder, which this requirement does not constrain.

**GWT**:
- Given the tracked skill files of this repository
- When each is searched for calendar dates, for status words tied to work
  in progress, and for pull-request, issue, commit and ticket references
- Then the search finds none
- Given the agent adds a rule to a skill file after an incident
- When the turn ends
- Then the skill file states the rule and, at most, the URL or path of its
  source; the date, the incident and the pull request that carried the fix
  are in a document under `references/` or nowhere
- Given a document under a skill's `references/` folder that holds dates
  and pull-request references
- When the skill files are cleaned
- Then that document is unchanged

## §change-carries-its-evidence

**EARS**: When the agent changes an instruction file, a skill, a hook or a
setting for this work, the record of that change shall give the reason for
it as at least one of: the URL of a primary source the agent read in full,
with the passage it relies on quoted; or a measurement taken on this
machine, with the command that reproduces it. Where the reason is that the
change makes one of the owner's corrections stop, the record shall give a
measurement and not only a source.

A summary produced by a fetching tool is not a source read in full. A
source that was read only in part is cited with the parts that were not
read. The record lives with the work documents under `references/`, so
that §skill-file-holds-no-point-in-time-content still holds.

**GWT**:
- Given a change that shortens skill descriptions on the grounds that a
  published guide recommends it
- When the change is recorded
- Then the record holds the guide's URL and the quoted sentence, and the
  agent obtained the page as raw text
- Given a change justified by "the covering skill is now loaded without
  being named"
- When the change is recorded
- Then the record holds a count taken before and a count taken after, by
  the same command, on this machine
- Given a paper of which the agent read the abstract and one section
- When the paper is cited
- Then the citation says which sections were not read

## §outcome-is-counted-the-way-the-baseline-was

**EARS**: When the changes of this work have been live for at least 14 days
and the owner's personal profile has recorded at least 200 sessions since
they went live, the agent shall count the owner's corrections again with
the same commands and the same reading rules that produced the baseline,
and shall report the count for each of the three corrections beside its
baseline. The outcome of `intent.md` is reached when the count is zero for
each of the three and no tracked skill file breaks
§skill-file-holds-no-point-in-time-content. If a count is not zero, then
each correction found shall be reported with the requirement of this
specification it shows broken, or with the statement that no requirement
covers it.

The three corrections are: the owner pointing at a loose end; the owner
naming a skill the agent should have loaded; the owner objecting to
point-in-time content in a skill file. The count covers only sessions of
the personal profile, and what reaches this repository is the count and
the kind of error, never the content of another project.

**GWT**:
- Given the baseline of 30 owner messages in 20 sessions that point at a
  loose end
- When the count is taken again over the sessions since the changes went
  live, with the same commands
- Then the report shows the new number of messages and sessions beside 30
  and 20, and the number of sessions that were counted
- Given a recount that finds two messages in which the owner names a skill
  the agent had not loaded
- When the report is written
- Then the outcome is reported as not reached, and each of the two messages
  is tied to §covering-skill-loaded-before-acting or stated as not covered
- Given only 9 days or only 120 sessions since the changes went live
- When a recount is asked for
- Then the report gives the numbers so far and says that the period is not
  yet complete
