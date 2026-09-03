---
name: smith-principles
description: Fundamental coding principles
---

# Fundamental Coding Principles

**Load if:** Always active (foundation for all development)
**Prerequisites:** None

## Critical Rules

- MUST apply DRY before adding features
- MUST apply KISS to choose simplest solution
- MUST apply YAGNI to defer unneeded implementation
- One reason to change per module (Single Responsibility)
- Open for extension, closed for modification (Open/Closed)
- Subtypes substitutable for base types (Liskov Substitution)
- Many specific interfaces over one general (Interface Segregation)
- Depend on abstractions, not concretions (Dependency Inversion)
- Complete coverage without overlap (MECE)
- Fewest assumptions (Occam's Razor)
- Simplicity requires effort (SINE)

## Related

- @smith-standards/SKILL.md - Universal coding standards
- @smith-guidance/SKILL.md - AI agent behavior (HHH framework)

## Before You Finish

**Before implementing:** Check for existing abstractions (DRY), choose simplest approach (KISS), confirm feature is needed now (YAGNI), verify SOLID principles, verify MECE, Occam's Razor, and SINE
