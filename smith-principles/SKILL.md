---
name: smith-principles
description: Fundamental coding principles (DRY, KISS, YAGNI, SOLID). Always active. Use when starting a development task, choosing an approach, or reviewing code quality.
---

# Fundamental Coding Principles

**Prerequisites:** None

## Critical Rules

- Apply DRY before adding features
- Apply KISS: choose the simplest solution
- Apply YAGNI: defer unneeded implementation
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
- @smith-guidance/SKILL.md - AI agent behavior (safety rules, anti-sycophancy)

## Before You Finish

**Before implementing:** Check for existing abstractions (DRY), choose simplest approach (KISS), confirm feature is needed now (YAGNI), verify SOLID principles, verify MECE, Occam's Razor, and SINE
