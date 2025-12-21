# C.L.E.O. Transition & Multi-Agent Support Plan

**Goal:** Decouple `claude-todo` from Claude-specific branding, rebrand to **CLEO (Comprehensive Logistics & Execution Orchestrator)**, and introduce multi-agent support for Gemini, Kimi, and Codex.

**Target Version:** v1.0.0
**Current Status:** PAUSED (Completing v0.24.x pre-requisites on `main`)

---

## 0. Phase 0: Pre-Requisites (Main Branch)
**Objective:** Ensure the core system is stable and feature-complete before the rebranding refactor.

*   **Hierarchy System**: Ensure `maxSiblings` and `maxDepth` logic is solid (T328 series).
*   **Archive Enhancements**: Complete the smart archive system (T429 series).
*   **Analysis Engine**: Finish "Smart Analyze" (T542).
*   **Compliance**: Ensure "LLM-Agent-First" spec v3.0 compliance (T481 series).

---

## 1. Executive Summary

C.L.E.O. (Comprehensive Logistics & Execution Orchestrator) acts as the persistent memory and logistics layer for *any* CLI-based AI agent. The transition involves:
1.  **Rebranding**: `claude-todo` → `cleo`.
2.  **Generalization**: Abstracting `.claude/` directories to `.cleo/`.
3.  **Multi-Agent Ecosystem**: Native support for **concurrent** agents (Claude, Gemini, Kimi, Codex) interacting with the same project.
4.  **Sync R&D**: Research and design a universal `sync` command that adapts to each agent's native task API.

## 2. Architectural Changes

### A. Configuration Schema Expansion (`schemas/config.schema.json`)

We will add an `agents` section (plural) to support multiple active agents.

```json
"agents": {
  "type": "object",
  "properties": {
    "active": {
      "type": "array",
      "items": { "type": "string", "enum": ["claude", "gemini", "kimi", "codex"] },
      "default": ["claude"],
      "description": "List of active agents enabled for this project."
    },
    "configs": {
      "type": "object",
      "properties": {
        "claude": { "type": "object", "properties": { "docsFile": { "const": "CLAUDE.md" } } },
        "gemini": { "type": "object", "properties": { "docsFile": { "const": "AGENTS.md" } } },
        "kimi": { "type": "object", "properties": { "docsFile": { "const": "INSTRUCTIONS.md" } } },
        "codex": { "type": "object", "properties": { "docsFile": { "const": "INSTRUCTIONS.md" } } }
      }
    }
  }
}
```

### B. Directory Structure & Naming

*   **Global Home**: `~/.claude-todo` → `~/.cleo`
*   **Project Directory**: `.claude/` → `.cleo/`
*   **Legacy Fallback**: A migration script will be provided. Post-migration, the system will look for `.cleo/` only, to maintain clean logic.

---

## 3. Implementation Steps

### Phase 1: Templating & Branding
1.  **Create `templates/AGENT-INJECTION.md`**: Generic CLEO instructions.
2.  **Create Agent-Specific Headers**:
    *   `templates/agents/GEMINI-HEADER.md`
    *   `templates/agents/KIMI-HEADER.md`
    *   `templates/agents/CODEX-HEADER.md`

### Phase 2: Core Library Updates (Config & Logging)
*   Refactor `config.sh` and `logging.sh` to support `CLEO_*` env vars and remove hardcoded "claude" references.

### Phase 3: Initialization & Installation (`install.sh`, `init.sh`)

**Crucial Change**: Installation and Initialization are now **Multi-Select**.

1.  **Update `scripts/install.sh`**:
    *   **Interactive Selection**: "Which agents do you use? [x] Claude [ ] Gemini [x] Kimi"
    *   **Global Config**: Write enabled agents to `~/.cleo/config.json`.
    *   **Path Setup**: Ensure paths like `.gemini/`, `.kimi/` are known/created if standard.

2.  **Update `scripts/init.sh`**:
    *   **Loop Processing**: Iterate through all enabled agents in `agents.active`.
    *   **Gemini Logic**:
        *   Check/Create `.gemini/settings.json`.
        *   Update `contextFileName` to include `AGENTS.md` (via `jq`).
        *   Inject/Append instructions to `AGENTS.md`.
    *   **Claude Logic**:
        *   Inject/Append to `CLAUDE.md`.
    *   **Kimi/Codex Logic**:
        *   Inject/Append to `INSTRUCTIONS.md`.

---

## 4. Sync System - Research & Design Phase

**Objective**: Create a universal `cleo sync` command that adapts to the active agent's native toolset.

### 4.A: Target Implementation (Examples)

The sync adapter must transform CLEO tasks into these specific formats:

*   **Gemini (`write_todos`)**:
    *   Source: `https://geminicli.com/docs/tools/todos/`
    ```javascript
    write_todos({
      todos: [
        { description: 'Initialize new React project', status: 'completed' },
        { description: 'Implement state management', status: 'in_progress' },
        { description: 'Create API service', status: 'pending' },
      ],
    });
    ```

*   **Kimi (`SetTodoList`)**:
    *   Source: `https://llmmultiagents.com/en/blogs/kimi-cli-technical-deep-dive`
    ```python
    SetTodoList(todos=[
        {"content": "Analyze code structure", "status": "completed"},
        {"content": "Write unit tests", "status": "in_progress"}
    ])
    ```

*   **Claude (TodoWrite)**:
    *   Existing implementation using `content`, `activeForm`, `status`.

### 4.B: Active Agent Detection

To determine *which* adapter to use during a session:

1.  **Session Start**: The agent starts a session with an identity flag.
    *   `cleo session start --agent gemini`
2.  **State Persistence**: This writes to `.cleo/session.json`.
    ```json
    { "activeAgent": "gemini", "sessionId": "..." }
    ```
3.  **Sync Execution**: `cleo sync` reads `activeAgent` from `session.json` and loads the matching adapter (e.g., `lib/sync/gemini_adapter.sh`) to format the output correctly (e.g., calling `write_todos` vs `SetTodoList`).

---

## 5. Multi-Agent CLI Experience

| Feature | Claude Code | Gemini CLI | Kimi CLI | Codex CLI |
| :--- | :--- | :--- | :--- | :--- |
| **Command** | `claude-todo` / `ct` | `cleo` | `cleo` | `cleo` |
| **Context File** | `CLAUDE.md` | `AGENTS.md` | `INSTRUCTIONS.md` | `INSTRUCTIONS.md` |
| **Sync Tool** | TodoWrite | `write_todos` | `SetTodoList` | Text/JSON Injection |
| **Status Mapping** | `active` -> `in_progress` | `active` -> `in_progress` | `active` -> `in_progress` | Text-based |

---

## 6. Verification Plan

*   **Mock Project**: `/mnt/projects/cleo-testing`
*   **Test Cases**:
    1.  **Multi-Agent Init**: Run `cleo init` with Claude + Gemini enabled. Verify *both* `CLAUDE.md` and `AGENTS.md` are updated.
    2.  **Gemini Config**: Verify `.gemini/settings.json` is correctly patched using `jq`.
    3.  **Agent Detection**: Verify `cleo session start --agent gemini` correctly creates `.cleo/session.json` with the right `activeAgent`.

---

## 7. Q&A Clarifications

### Q1: Can I have Claude AND Gemini active?
**Answer**: Yes. `cleo init` will check your config (or flags) and update *both* `CLAUDE.md` and `AGENTS.md` (and `.gemini/settings.json`). This allows you to switch agents mid-project and have both fully context-aware.

### Q2: Why "C.L.E.O."?
**Answer**: "Comprehensive Logistics & Execution Orchestrator". It emphasizes that the tool handles the *logistics* (state, history, files) so the agent can focus on *execution* (coding).

### Q3: What about the `sync` command?
**Answer**: It becomes a polymorphic tool. `cleo sync --inject` pushes the current `active` tasks to the *active agent's* buffer using the specific adapter logic defined in Section 4.A.
