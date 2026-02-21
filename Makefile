.PHONY: install install-dev update clean test lint format help

# Default target
all: install

## install: Install dependencies and the package in editable mode
install:
	uv sync --no-dev

## install-dev: Install dependencies with development tools
install-dev:
	uv sync

## update: Update dependencies to latest compatible versions
update:
	uv sync --upgrade

## clean: Remove the virtual environment and lock file
clean:
	rm -rf .venv uv.lock

## test: Run tests using pytest
test:
	uv run pytest

## lint: Run ruff linting
lint:
	uv run ruff check nanobot/

## format: Format code with ruff
format:
	uv run ruff format nanobot/

## shell: Spawn a shell in the virtual environment
shell:
	uv shell

## run: Run a command in the virtual environment (usage: make run CMD="nanobot status")
run:
	uv run $(CMD)

## help: Show this help message
help:
	@echo "Available commands:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /' | column -t -s ':'
