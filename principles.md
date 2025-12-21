# Fundamental Coding Principles

<metadata>

- **Load if**: Always active (foundation for all development)
- **Prerequisites**: None

</metadata>

## CRITICAL (Primacy Zone)

<required>

- MUST apply DRY before adding features
- MUST apply KISS to choose simplest solution
- MUST apply YAGNI to defer unneeded implementation

</required>

<forbidden>

- Violating Single Responsibility (one reason to change)
- Creating tight coupling (depend on abstractions instead)
- Duplicating code that could be abstracted

</forbidden>

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

<related>

- @standards.md - Universal coding standards
- @guidance.md - AI agent behavior (HHH framework)

</related>

## ACTION (Recency Zone)

<required>

**Before implementing:**
1. Check for existing abstractions (DRY)
2. Choose simplest approach (KISS)
3. Confirm feature is needed now (YAGNI)
4. Verify single responsibility (SOLID-S)

</required>
