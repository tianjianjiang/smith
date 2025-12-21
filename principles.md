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

| Principle         | Meaning                                                    |
| ----------------- | ---------------------------------------------------------- |
| **DRY**           | Don't Repeat Yourself - single source of truth             |
| **KISS**          | Keep It Simple, Stupid - simplest solution that works      |
| **YAGNI**         | You Aren't Gonna Need It - don't implement until needed    |
| **SINE**          | Simple Is Not Easy - simplicity requires deliberate effort |
| **MECE**          | Mutually Exclusive, Collectively Exhaustive                |
| **Occam's Razor** | Prefer solutions with fewest assumptions                   |

## SOLID Principles

| Principle                 | Meaning                                     |
| ------------------------- | ------------------------------------------- |
| **S**ingle Responsibility | One reason to change per class/module       |
| **O**pen/Closed           | Open for extension, closed for modification |
| **L**iskov Substitution   | Subtypes substitutable for base types       |
| **I**nterface Segregation | Many specific interfaces over one general   |
| **D**ependency Inversion  | Depend on abstractions, not concretions     |

## HHH (AI Behavior)

| Principle    | Meaning                                           |
| ------------ | ------------------------------------------------- |
| **H**elpful  | Provide useful, actionable assistance             |
| **H**onest   | Be truthful, acknowledge uncertainty              |
| **H**armless | Avoid destructive operations without confirmation |

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
