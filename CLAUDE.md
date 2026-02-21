# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

nanobot is an ultra-lightweight personal AI assistant (~4,000 lines of core code) that provides multi-channel chatbot functionality with LLM integration. It supports multiple chat platforms (Telegram, Discord, WhatsApp, Slack, Email, Feishu, QQ, DingTalk, Mochat) and multiple LLM providers (OpenRouter, Anthropic, OpenAI, DeepSeek, Gemini, etc.).

**Key Design Philosophy:** Minimal, readable code that's easy to extend and modify for research and development.

## Development Commands

### Installation & Setup
```bash
# Install dependencies (uses uv package manager)
make install

# Install with development tools
make install-dev

# Alternative: Using uv directly
uv sync              # Install with dev dependencies
uv sync --no-dev     # Install runtime dependencies only

# Initialize config and workspace
nanobot onboard

# Run tests
make test
# Or: uv run pytest

# Run a specific test
uv run pytest tests/test_commands.py::test_onboard_fresh_install

# Linting
make lint
make format
# Or: uv run ruff check nanobot/
#     uv run ruff format nanobot/
```

### Available Make Commands
```bash
make install        # Install runtime dependencies
make install-dev    # Install with dev tools (pytest, ruff)
make update         # Update dependencies to latest compatible versions
make clean          # Remove virtual environment and lock file
make test           # Run tests
make lint           # Run ruff linting
make format         # Format code with ruff
make shell          # Spawn shell in virtual environment
make run CMD="..."  # Run a command in the virtual environment
make help           # Show all available commands
```

### Running the Application
```bash
# Interactive CLI mode
nanobot agent

# Single message
nanobot agent -m "Hello"

# Start gateway (connects to all enabled channels)
nanobot gateway

# Show status
nanobot status
```

### Testing Channels
```bash
# Test individual channel (requires config in ~/.nanobot/config.json)
nanobot gateway
```

## Architecture Overview

### Message Flow Architecture

The system uses a **message bus pattern** that decouples chat channels from the agent core:

```
Channel → MessageBus.inbound → AgentLoop → LLM + Tools → MessageBus.outbound → Channel
```

**Key Components:**
- **`nanobot/bus/queue.py`**: Async message bus with inbound/outbound queues
- **`nanobot/bus/events.py`**: InboundMessage/OutboundMessage event types
- **`nanobot/agent/loop.py`**: Core agent processing engine (LLM ↔ tool execution loop)
- **`nanobot/channels/`**: Platform-specific channel implementations
- **`nanobot/session/manager.py`**: Conversation history persistence (JSONL format)

### Agent Processing Loop

The `AgentLoop` class (`nanobot/agent/loop.py`) is the heart of the system:

1. Receives messages from bus
2. Builds context with history, memory, skills
3. Calls LLM with tool definitions
4. Executes tool calls (shell, filesystem, web, spawn, etc.)
5. Sends responses back to bus
6. Consolidates long conversations to memory files

**Important:** Messages are append-only for LLM cache efficiency. Consolidation writes summaries to `MEMORY.md`/`HISTORY.md` but doesn't modify the message list.

### Provider Registry

**Single Source of Truth:** `nanobot/providers/registry.py` contains all LLM provider metadata.

**Adding a new provider is just 2 steps:**
1. Add a `ProviderSpec` entry to `PROVIDERS` in `registry.py`
2. Add a field to `ProvidersConfig` in `config/schema.py`

Environment variables, model prefixing, config matching, and status display all derive from the registry automatically—no if-elif chains to touch.

**Provider types:**
- **Gateways** (OpenRouter, AiHubMix): Route any model, detected by API key prefix
- **Direct providers** (Custom): Bypass LiteLLM, connect directly to OpenAI-compatible endpoints
- **OAuth providers** (OpenAI Codex): Use OAuth flow instead of API keys

### Tools System

Tools are registered in `nanobot/agent/tools/registry.py` and executed by the agent loop.

**Built-in tools:**
- `shell`: Execute shell commands (with security restrictions)
- `read_file`, `write_file`, `edit_file`, `list_dir`: Filesystem operations
- `web_search`, `web_fetch`: Web access via Brave Search API
- `message`: Send messages to channels
- `spawn`: Launch background subagents
- `cron`: Schedule tasks

**Tool base class:** `nanobot/agent/tools/base.py` - Abstract `Tool` class with:
- `name`, `description`, `parameters` (JSON Schema)
- `execute(**kwargs)` - async method
- Built-in parameter validation

**Adding a new tool:**
1. Create a class inheriting from `Tool`
2. Implement the required properties and execute method
3. Register in `AgentLoop._register_default_tools()`

### Skills System

Skills are markdown files (`SKILL.md`) that teach the agent how to use specific tools or perform tasks. They're loaded by `SkillsLoader` from:
- `~/.nanobot/workspace/skills/` (user skills, highest priority)
- `nanobot/skills/` (built-in skills: github, weather, tmux, cron, memory, etc.)

**Bundled skills:** clawhub, cron, github, memory, skill-creator, summarize, tmux, weather

### Subagent System

Background task execution via `SubagentManager` (`nanobot/agent/subagent.py`):
- Spawns lightweight agent instances with isolated context
- Shares LLM provider but runs in separate asyncio tasks
- Announces results back to origin channel

### Configuration

**Config file:** `~/.nanobot/config.json`

**Schema:** Pydantic models in `nanobot/config/schema.py`
- Accepts both camelCase and snake_case keys
- Channel configs: `TelegramConfig`, `DiscordConfig`, `EmailConfig`, etc.
- Provider configs: `ProvidersConfig` with per-provider settings
- Tools config: `restrictToWorkspace` for sandboxing

**Workspace:** `~/.nanobot/workspace/`
- `sessions/`: Conversation history (JSONL files)
- `skills/`: User-defined skills
- `MEMORY.md`: Consolidated long-term memory
- `HISTORY.md`: Conversation summaries

### MCP (Model Context Protocol)

nanobot supports MCP servers for external tool integration. Configuration format is compatible with Claude Desktop/Cursor.

**Config location:** `tools.mcpServers` in config.json

**Transport modes:**
- **Stdio:** Local process via `npx`/`uvx` with `command` + `args`
- **HTTP:** Remote endpoint with `url` + optional `headers`

MCP tools are auto-discovered and registered on startup.

## Testing Patterns

Tests use `pytest` with async support and `typer.testing.CliRunner` for CLI commands.

**Key patterns:**
- `mock_paths` fixture: Isolates config/workspace to temp directories
- Test files: `tests/test_commands.py`, `tests/test_email_channel.py`, etc.

## Channel Integration

Each channel in `nanobot/channels/`:
- Inherits from `BaseChannel` (in `base.py`)
- Converts platform-specific messages to `InboundMessage`
- Converts `OutboundMessage` to platform-specific responses
- Manages platform connection lifecycle

**Channel manager:** `channels/manager.py` handles all enabled channels concurrently.

## Security Considerations

- **Workspace restriction:** Set `"tools.restrictToWorkspace": true` to sandbox file/shell tools
- **Channel allowlists:** `channels.*.allowFrom` restricts who can interact
- **Shell command validation:** ExecTool respects `allowedCommands` and `blockedCommands` from config

## Key Files to Understand

- `nanobot/agent/loop.py:35-100` - AgentLoop initialization and core processing
- `nanobot/providers/registry.py:72-100` - Provider registry with examples
- `nanobot/bus/queue.py:8-44` - Message bus architecture
- `nanobot/agent/tools/base.py:7-53` - Tool base class and validation
- `nanobot/session/manager.py:14-80` - Session management and persistence

## Development Workflow

1. **Adding a new LLM provider:** Edit `registry.py` + `schema.py` (2 files max)
2. **Adding a new channel:** Create `channels/newchannel.py` + add config class
3. **Adding a new tool:** Create tool class + register in `AgentLoop._register_default_tools()`
4. **Adding a new skill:** Create `nanobot/skills/myskill/SKILL.md`
