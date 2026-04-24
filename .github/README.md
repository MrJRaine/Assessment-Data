# Copilot Customization & Skills

This directory contains project-specific Copilot customizations and domain knowledge for the Assessment-Data project.

## Structure

### `skills/`
Custom workflow skills created for this project. Each skill is in its own subdirectory with a `SKILL.md` file.

**Usage**: These appear as `/skillname` slash commands in Copilot chat.

**When to create**: Multi-step workflows with bundled assets that apply to specific project tasks.

**Example**: `skills/data-validation/SKILL.md`

---

### `instructions/`
File-level instructions that guide Copilot behavior for specific file patterns.

**Usage**: Applied via `applyTo` glob patterns or triggered on-demand based on file context.

**When to create**: Consistent patterns, conventions, or requirements for specific file types (e.g., `*.md`, `src/api/**`).

**Files**: `*.instructions.md` format with YAML frontmatter specifying `applyTo` patterns.

**Example**: `instructions/data-pipeline.instructions.md`

---

### `prompts/`
Reusable, parameterized prompts for specific tasks within the project.

**Usage**: Appear as `/promptname` slash commands in Copilot chat.

**When to create**: Single, focused tasks with parameterized inputs (vs. multi-step skills).

**Files**: `*.prompt.md` format with YAML frontmatter.

**Example**: `prompts/validate-dataset.prompt.md`

---

### `agents/`
Custom agents for specialized workflows, context isolation, or multi-stage processes.

**Usage**: Can be invoked as subagents or used for specific task categories.

**When to create**: Need different tool restrictions per stage, or context isolation for complex flows.

**Files**: `*.agent.md` format with YAML frontmatter.

**Example**: `agents/data-reviewer.agent.md`

---

## Repository Memories

Project-scoped facts and insights are stored in `/memories/repo/` (accessible to Copilot during work on this project):
- Codebase conventions
- Build and deployment commands
- Verified solutions to common problems
- Project structure notes

These persist across conversations on this project.

---

## Getting Started

1. **Create a new skill**: Add a subdirectory under `skills/` with a `SKILL.md` file
2. **Create instructions**: Add `*.instructions.md` files under `instructions/` with frontmatter and glob patterns
3. **Create a prompt**: Add a `*.prompt.md` file under `prompts/` with parameterized inputs
4. **Create an agent**: Add an `*.agent.md` file under `agents/` for complex workflows

All files use YAML frontmatter between `---` markers at the top. See reference documentation for specific formats.
