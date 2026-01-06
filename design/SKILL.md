---
name: design
description: SOLID principles and architecture design patterns. Use when starting new features, refactoring code, conducting architecture reviews, or applying object-oriented design principles.
---

# Design Principles

<metadata>

- **Scope**: SOLID principles for OOP/architecture design
- **Load if**: Starting new feature, refactoring, architecture review
- **Prerequisites**: @principles/SKILL.md (fundamental principles: DRY, KISS, YAGNI, MECE)

</metadata>

## SOLID Principles

<required>

- **S**ingle Responsibility: One reason to change per class/module
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable for base types
- **I**nterface Segregation: Many specific interfaces over one general
- **D**ependency Inversion: Depend on abstractions, not concretions

</required>

## ACTION (Recency Zone)

<required>

**When designing or reviewing architecture:**
1. Apply Single Responsibility - each module has one reason to change
2. Design for extension without modification (Open/Closed)
3. Ensure subtypes are substitutable (Liskov)
4. Prefer small, focused interfaces (Interface Segregation)
5. Depend on abstractions, not implementations (Dependency Inversion)

</required>

<related>

- @principles/SKILL.md - Fundamental principles (DRY, KISS, YAGNI)
- @standards/SKILL.md - Universal code standards
- `@dev/SKILL.md` - Development workflow
- `@analysis/SKILL.md` - Problem decomposition before design

</related>
