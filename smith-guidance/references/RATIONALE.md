# smith-guidance: rationale and sources

Background for rules stated in `smith-guidance/SKILL.md`. The rules live
there; this file only explains them.

## Making Changes

- Refactorings belong in a separate change from feature or bugfix work,
  except small cleanups such as a variable rename: Google engineering
  practices, "Separate Out Refactorings"
  (https://google.github.io/eng-practices/review/developer/small-cls.html).
- Review research recommends roughly 200-400 lines per review, with defect
  discovery diminishing beyond that size:
  https://smartbear.com/learn/code-review/best-practices-for-peer-code-review/

## Elaborate before asking

The rule closes two rationalizations:

- Asking "how should I handle the 62 «coined-term» cases?" when
  «coined-term» is a word you coined and never defined: the user must
  reverse-engineer the vocabulary before they can read the question.
- Treating a long investigation as permission to skip the write-up: the
  longer the investigation, the less of it the user has seen.
