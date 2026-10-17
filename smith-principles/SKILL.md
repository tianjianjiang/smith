---
name: smith-principles
description: Fundamental coding principles (DRY, KISS, YAGNI, SOLID). Always active. Use when starting a development task, choosing an approach, or reviewing code quality.
---

# Fundamental Coding Principles

**Prerequisites:** None
**Sources:** `references/SOURCES.md`

## Critical Rules

- Apply DRY before adding features
  - DRY means one representation per piece of knowledge, not per code
    text; look-alike code can be a coincidence
- Apply KISS: choose the simplest solution
  - Simplest in the SINE sense below, not the most familiar
- Apply YAGNI: defer unneeded implementation
  - It presumes code that stays easy to change; it does not forbid
    making code easy to change or excuse half-done work
- One reason to change per module (Single Responsibility)
  - A reason is a person or role who asks for changes, not "does one
    thing"
- Open for extension, closed for modification (Open/Closed)
- Subtypes substitutable for base types (Liskov Substitution)
  - Substitutable in behavior, not only in signature or by inheritance
- Many specific interfaces over one general (Interface Segregation)
- Depend on abstractions, not concretions (Dependency Inversion)
- Complete coverage without overlap (MECE)
  - Exhaustive of a stated whole; name the boundary or an "other" group
- Fewest assumptions (Occam's Razor)
  - Among options that explain the evidence equally well; it does not
    claim the simpler option is more likely true
  - Before removing something, state its purpose and why that purpose
    no longer holds (Chesterton's fence)
- Say what a thing is not when a positive claim would overreach (via
  negativa)
  - It is not deletion; deletion belongs to Occam's Razor
- Simple is not easy (SINE): simple means not entangled; easy means
  familiar or near at hand, and simplicity takes effort

## Related

- @smith-standards/SKILL.md - Universal coding standards
- @smith-guidance/SKILL.md - AI agent behavior (safety rules, anti-sycophancy)

## Before You Finish

**Before implementing:** Check for existing abstractions (DRY), choose simplest approach (KISS), confirm feature is needed now (YAGNI), verify SOLID principles, verify MECE, Occam's Razor, and SINE
