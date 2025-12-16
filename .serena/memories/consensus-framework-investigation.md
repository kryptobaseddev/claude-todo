# Phase Framework Consensus Investigation

## Date: 2025-12-15

## Research Scope
12 parallel agents investigated:
- 6 codebase exploration agents
- 6 deep research agents (industry standards, AI patterns, best practices)

## Key Consensus Findings

### 1. How Phases Actually Work in claude-todo
- **Static Labels**: Phases are metadata labels, NOT workflow states
- **No Automatic Movement**: Tasks do not move through phases automatically
- **Optional**: 31% of tasks have no phase assigned (schema allows null)
- **Independent from Status**: Phase and status are orthogonal dimensions
- **No Progression Enforcement**: No logic requires setup complete before core

### 2. Industry Standards
| Methodology | Phase Count | Focus |
|-------------|-------------|-------|
| Kanban | 3-5 | Status-based (To Do → Done) |
| Agile/Scrum | 5 | Sprint lifecycle |
| SDLC | 7 | Project lifecycle |
| DevOps | 8 | Continuous loop |
| Enterprise Tools | Separate | Phases + Status as distinct dimensions |

### 3. "setup→core→polish" vs Industry
- **No Direct Match**: This terminology is custom/proprietary
- **Closest Analogy**: Simplified SDLC (Planning+Design → Development → Testing+Deployment)
- **Not Status-Based**: Unlike industry-standard workflow columns

### 4. Correct Model (Confirmed by Research)
```
PHASES = What PART of project (categorization)
STATUS = WHERE in workflow (progression)
```

Tasks BELONG TO phases but MOVE THROUGH statuses.

### 5. AI Agent Patterns (2025)
- Cursor, Copilot Workspace, Devin, Windsurf use plan-execute-validate
- TodoWrite (Claude Code) is ephemeral, session-only
- No major agent uses phase-based progression

## Recommendations

### What's Working Well
1. Phase/status separation is architecturally sound
2. Optional phases provide flexibility
3. Phase visualization (progress bars) is valuable
4. Focus-based phase bonus in `next` command is sensible

### Potential Improvements
1. **Clarify Documentation**: Explicitly state phases are categorization, not workflow
2. **Consider Renaming**: "setup→core→polish" could become "foundation→implementation→refinement" for clarity
3. **Add 4th Phase Option**: Consider "testing" or "review" for quality gates
4. **Default Phase Strategies**: Offer templates (linear, iterative, component-based)

### When 3 Phases Work
- Solo/small projects
- Simple processes
- Projects without strict compliance

### When More Phases Help
- Quality gates needed → add "review"
- Deployment tracking → add "released"
- Testing emphasis → add "testing"

## Sources Consulted
- Atlassian (Jira, Agile workflows)
- GitHub (Projects, CLI)
- Linear, Asana, Monday.com
- Taskwarrior, Todo.txt, dstask
- Azure DevOps, AWS
- Cursor, Copilot Workspace, Devin, Windsurf
- PMI, SDLC methodologies
