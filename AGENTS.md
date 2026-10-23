# For Every Dawn Repository Guide

This file is the central Codex instruction file for this repository.

If `CLAUDE.md` also exists, keep the tracking sections aligned and treat `AGENTS.md` as the Codex-first source of truth.

## Project Contract

For Every Dawn is a Godot modern-warfare RTS inspired by Red Alert 2's pace and accessible command. Preserve the full-game vision of infantry, land, air, sea, and drones; meaningful terrain; easy squad controls; and high production quality with smooth runtime performance.

The repository now contains a Godot 4.5.1 tactical RTS prototype and automated checks. Do not report proposed architecture, aspirational AAA quality, or performance targets as implemented or measured. Follow the first playable slice before expanding content. Record assumptions as provisional until validated.

Use original or appropriately licensed assets. Favor small runnable increments, data-driven unit definitions, and profiler evidence. Keep controls and battlefield readability central when adding tactical complexity. Pin the engine version and document verified commands once the Godot project exists.

## Source Of Truth

When documents disagree, use this precedence:

1. `AGENTS.md`
2. `docs/architecture.md`
3. `docs/development-plan.md`
4. `docs/todo.md`
5. `docs/changelog.md`
6. `README.md`

## Project Tracking Documents

All tracking docs live in `docs/`. Detailed implementation plans live in `docs/plans/`.

### Document Inventory

| File | Purpose | When to Read | When to Update |
|------|---------|--------------|----------------|
| `docs/todo.md` | High-level task list grouped by phase, linked to plan files | Start of session to pick up work | After completing or discovering tasks |
| `docs/plans/N-name.md` | Detailed breakdown of a buildable unit | When working on that plan | Check off sub-tasks as you complete them |
| `docs/changelog.md` | Log of completed work, latest first | Before starting work to avoid redoing it | After every meaningful change |
| `docs/architecture.md` | Tech stack, directory layout, conventions, patterns | Before writing code | When adding modules, changing structure, or setting new patterns |
| `docs/bugs.md` | Known issues, failed approaches, workarounds | Before debugging or proposing risky changes | When discovering bugs or failed approaches |
| `docs/development-plan.md` | Vision, roadmap, and current delivery focus | At session start when scope matters | Only when scope, milestones, or priorities change |
| `README.md` | User-facing overview, setup, and usage | Before changing user-facing behavior | When setup, commands, or product surface changes |
| `docs/llm-api-guide.md` | Optional LLM-facing API or DSL reference | Before writing agent-facing examples or contracts | Update it whenever callable surfaces, schemas, or examples change |

## Session Start Protocol

1. Read `docs/todo.md`
2. Read the active plan in `docs/plans/`
3. Read the latest entries in `docs/changelog.md`
4. Read `docs/architecture.md`
5. Read `docs/development-plan.md` only when the task touches scope or roadmap decisions

## After Each Modification

- Update the active plan file and check off finished sub-tasks
- Update `docs/todo.md` to reflect completed or newly discovered work
- Add a new top entry to `docs/changelog.md`
- Update `docs/architecture.md` when layout, patterns, or dependencies change
- Update `docs/bugs.md` when you hit a bug or abandon an approach
- Update `docs/development-plan.md` only when priorities or milestones change
- Update `README.md` when setup, commands, or user-facing behavior changes
- If present, update `docs/llm-api-guide.md` when callable surfaces, schemas, or examples change

## Plan Files

Plans use hierarchical numbering that mirrors the task tree:

```text
plans/
  1-name.md
  1-1-name.md
  1-2-name.md
  2-name.md
  2-1-name.md
  2-1-1-name.md
```

Top-level plans omit a parent link. Sub-plans link back to their parent. Create deeper levels only when the work is active.

### Plan File Format

```markdown
# 1-1: Sub-Plan Title

**Parent:** [1-name](1-name.md)
**Status:** not-started | in-progress | completed
**Goal:** One sentence describing what this plan achieves.

## Tasks
- [ ] 1. Task
  - [ ] 1-1. Sub-task
  - [ ] 1-2. Sub-task
- [ ] 2. Task

## Decisions
- (filled in during execution)

## Notes
- (filled in during execution)
```

### Todo Format

```markdown
# Todo

## Phase 0 - Phase Name
- [x] [1-name](plans/1-name.md) - brief description
  - [x] [1-1-name](plans/1-1-name.md)
  - [ ] [1-2-name](plans/1-2-name.md)
- [ ] 2: Description -> (not yet planned)

## Backlog
- [ ] Task description
```

## Rules

- Keep each document concise
- Keep changelog entries in descending order and never delete old entries
- Keep failed approaches in `docs/bugs.md` so the repo does not repeat them
- Expand plan depth just in time
- When in doubt, update the docs
