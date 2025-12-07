# IDE Path Variable Mappings

<context>

## Overview

Maps conceptual path variables to IDE-specific syntax. For variable definitions and usage, see [Naming Standards]($HOME/.smith/rules-naming.md#path-reference-standards).

## Conceptual Variables

**Defined in**: [Naming Standards]($HOME/.smith/rules-naming.md#path-reference-standards)
- `$WORKSPACE_ROOT` - Current workspace directory
- `$REPO_ROOT` - Monorepo root
- `$HOME` - User home directory

</context>

## IDE Syntax Mappings

### VS Code-Based IDEs (VS Code, Cursor, Kiro)

**Syntax**: `${variableName}`

**Common Variables**:
- `${workspaceFolder}` — Workspace root directory
- `${userHome}` — User home directory
- `${env:VAR}` — Environment variable
- `${config:key}` — Settings value

**Mappings**:
```
$WORKSPACE_ROOT  →  ${workspaceFolder}
$REPO_ROOT       →  ${env:REPO_ROOT} or ${workspaceFolder}/../../../../
$HOME            →  ${userHome}
```

**Multi-root workspaces**: Use `${workspaceFolder:folderName}` for specific folders

**Configuration**:
- **VS Code/Cursor**: `.vscode/settings.json`
- **Kiro**: `.kiro/settings/mcp.json` (workspace) or `~/.kiro/settings/mcp.json` (global)

**Note**: Kiro is VS Code-based (Code OSS fork) and inherits VS Code configuration system.

### JetBrains IDEs (PyCharm, IntelliJ IDEA)

**Syntax**: `$MACRO_NAME$`

**Common Macros**:
- `$PROJECT_DIR$` — Project root directory
- `$USER_HOME$` — User home directory

**Mappings**:
```
$WORKSPACE_ROOT  →  $PROJECT_DIR$
$REPO_ROOT       →  $PROJECT_DIR$/../../../../ (or custom path variable)
$HOME            →  $USER_HOME$
```

**Configuration**: File → Settings → Appearance & Behavior → Path Variables

<required>

## Best Practices

1. **Documentation**: Always use conceptual variables (`$WORKSPACE_ROOT`, `$REPO_ROOT`, `$HOME`)
2. **IDE Configs**: Translate to IDE-specific syntax using above mappings
3. **Cross-IDE Compatibility**: Prefer environment variables when possible
4. **Security**: Use variable references for sensitive values, never hardcode

</required>

## Reference

<related>

- **VS Code Variables**: [Documentation](https://code.visualstudio.com/docs/editor/variables-reference)
- **PyCharm Macros**: [Documentation](https://www.jetbrains.com/help/idea/absolute-path-variables.html)
- **Path Standards**: `$HOME/.smith/rules-naming.md`

</related>
