---
name: smith-principles
description: Fundamental coding principles (DRY, KISS, YAGNI, SOLID, HHH). Use when starting any development task, evaluating implementation approaches, or reviewing code quality. Always active as foundation for all development decisions.
---

# Fundamental Coding Principles

**Load if:** Always active (foundation for all development)
**Prerequisites:** None

## Critical Rules

- MUST apply DRY before adding features
- MUST apply KISS to choose simplest solution
- MUST apply YAGNI to defer unneeded implementation
- Keep one reason to change per class/module (Single Responsibility)
- Depend on abstractions, not concretions, to avoid tight coupling
- Abstract code that would otherwise be duplicated

## Core Principles

- **DRY (Don't Repeat Yourself)**: Single source of truth
- **KISS (Keep It Simple, Stupid)**: Simplest solution that works
- **YAGNI (You Aren't Gonna Need It)**: Don't implement until needed
- **SINE (Simple Is Not Easy)**: Simplicity requires deliberate effort
- **MECE (Mutually Exclusive, Collectively Exhaustive)**: Complete coverage without overlap
- **Occam's Razor**: Prefer solutions with fewest assumptions

## SOLID Principles

- **S (Single Responsibility)**: One reason to change per class/module
- **O (Open/Closed)**: Open for extension, closed for modification
- **L (Liskov Substitution)**: Subtypes substitutable for base types
- **I (Interface Segregation)**: Many specific interfaces over one general
- **D (Dependency Inversion)**: Depend on abstractions, not concretions

## HHH (AI Behavior)

- **H (Helpful)**: Provide useful, actionable assistance
- **H (Honest)**: Be truthful, acknowledge uncertainty
- **H (Harmless)**: Avoid destructive operations without confirmation

## Related

- @smith-standards/SKILL.md - Universal coding standards
- @smith-guidance/SKILL.md - AI agent behavior (HHH framework)

## Before You Finish

**Before implementing:**
1. Check for existing abstractions (DRY)
2. Choose simplest approach (KISS)
3. Confirm feature is needed now (YAGNI)
4. Verify single responsibility (SOLID-S)
