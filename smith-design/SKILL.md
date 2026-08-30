---
name: smith-design
description: Architecture design patterns and OOP practices
---

# Design Principles

**Scope:** Architecture design patterns applying SOLID (defined in @smith-principles/SKILL.md)
**Load if:** Starting new feature, refactoring, architecture review
**Prerequisites:** @smith-principles/SKILL.md (SOLID, DRY, KISS, YAGNI, MECE)

## Before You Finish

**When designing or reviewing architecture:**
1. Apply Single Responsibility - each module has one reason to change
2. Design for extension without modification (Open/Closed)
3. Ensure subtypes are substitutable (Liskov)
4. Prefer small, focused interfaces (Interface Segregation)
5. Depend on abstractions, not implementations (Dependency Inversion)

## Claude Code Plugin Integration

**When pr-review-toolkit is available:**

- **type-design-analyzer agent**: Rates type design on 4 dimensions (1-10 each)
  - Encapsulation
  - Invariant expression
  - Usefulness
  - Enforcement
- Trigger: "Review the «TypeName» type design" or use Task tool

## Related

- @smith-principles/SKILL.md - Fundamental principles (DRY, KISS, YAGNI)
- @smith-standards/SKILL.md - Universal code standards
- `@smith-dev/SKILL.md` - Development workflow
- `@smith-analysis/SKILL.md` - Problem decomposition before design
