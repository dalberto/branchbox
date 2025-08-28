# BranchBox

[![Tests](https://github.com/dalberto/branchbox/actions/workflows/badge.yml/badge.svg)](https://github.com/dalberto/branchbox/actions/workflows/badge.yml)
[![CI](https://github.com/dalberto/branchbox/actions/workflows/ci.yml/badge.svg)](https://github.com/dalberto/branchbox/actions/workflows/ci.yml)

Run multiple branches of your Docker Compose project simultaneously with automatic isolation.

## Quick Start

```bash
# Install
curl -sSL https://raw.githubusercontent.com/dalberto/branchbox/main/install.sh | bash

# Clone project
branchbox clone https://github.com/user/repo.git
cd repo-branchbox

# Create worktree
branchbox create feature-auth

# Start services
branchbox up feature-auth
```

## What It Does

BranchBox manages Git worktrees with Docker Compose isolation:
- **Separate containers/volumes** per branch via docker compose projects, and `COMPOSE_PROJECT_NAME`.
- **Preserves .env files** from main branch (API keys, secrets)
- **Shows actual ports** of running services
- **No port management** - your project handles that (see [Docker Setup](DOCKER_SETUP.md))

*Security Note: BranchBox copies existing .env files between worktrees by default.*

## Installation

```bash
# Install from GitHub
curl -sSL https://raw.githubusercontent.com/dalberto/branchbox/main/install.sh | bash

# Install from local directory (for development/testing)
./install.sh --local

# Manual install
chmod +x branchbox
mv branchbox /usr/local/bin/
```

The install script supports:
- **`--local`** - Install from current directory instead of GitHub
- **`--help`** - Show usage information
- **`INSTALL_DIR`** - Custom install location (default: `~/.local/bin`)
- **`GITHUB_TOKEN`** - For private repo access

## Commands

```bash
branchbox clone <repo-url> [--no-setup]  # Clone and setup project
branchbox create <name> [branch]         # Create worktree
branchbox up <name>                      # Start services
branchbox down <name> [--remove]         # Stop services (optionally remove)
branchbox status                         # Show all worktrees
branchbox remove <name>                  # Remove worktree
branchbox setup [name]                   # Run setup script for main or specified worktree
```

## Docker Compose Requirements

Your project must handle port conflicts. See [DOCKER_SETUP.md](DOCKER_SETUP.md) for strategies.

Basic example:
```yaml
services:
  web:
    ports:
      - "${APP_PORT:-8000}:8000"  # Use env var with default
```

## Directory Structure

```
myproject-branchbox/
├── main/              # Main branch
├── feature-auth/      # Feature branch
└── bugfix-api/        # Another branch
```

BranchBox sets `COMPOSE_PROJECT_NAME=myproject-feature-auth` when running services.

## Common Workflows

### Multiple Features
```bash
branchbox create auth
branchbox create new-api
branchbox up auth     # Shows actual ports
branchbox up new-api  # Different ports
```

### PR Review
```bash
branchbox create pr-123
branchbox up pr-123
# Test the PR...
branchbox down pr-123 --remove
```

## Setup Scripts

BranchBox can automatically run initialization scripts after cloning or creating worktrees. This is useful for:
- Pulling secrets from secret management systems
- Installing dependencies
- Running database migrations
- Setting up local configuration

### Creating a Setup Script

Add one of these files to your repository root:
- `.branchbox-setup.sh` (recommended - BranchBox specific)
- `setup.sh`, `init.sh`, or `bootstrap.sh` (common conventions)

Example setup script:
```bash
#!/bin/bash
echo "Setting up $BRANCHBOX_WORKTREE_NAME..."

# Install dependencies
npm install

# Pull secrets (example)
if [ "$BRANCHBOX_IS_MAIN" = "true" ]; then
    echo "Fetching secrets for main branch..."
    # vault read secret/myapp > .env
fi

# Run migrations
npm run migrate
```

### Setup Script Environment

Setup scripts receive these environment variables:
- `BRANCHBOX_WORKTREE_NAME` - Name of the current worktree (e.g., "main", "feature-auth")
- `BRANCHBOX_IS_MAIN` - "true" if running in main worktree, "false" otherwise
- `BRANCHBOX_PROJECT_NAME` - Name of the project

## Environment Variables

- `BRANCHBOX_COPY_ENV_FILES` - Copy .env files to worktrees (default: true)
- `BRANCHBOX_AUTO_SETUP` - Run setup after clone: true, false, or prompt (default: prompt)
- `BRANCHBOX_WORKTREE_SETUP` - Run setup in new worktrees (default: false)
- `BRANCHBOX_SETUP_SCRIPTS` - Colon-separated list of setup script names to search for

## Testing

The project includes comprehensive testing with both local and CI workflows.

### Test Suites

- **`quick.sh`** - Fast smoke tests for core functionality (26 tests, ~15 seconds)
- **`comprehensive.sh`** - Full test suite with detailed assertions (17 tests, ~90 seconds)

### Running Tests Locally

```bash
# Run all checks (syntax, linting, optional tests)
./check.sh

# Run specific test suites
cd tests
./quick.sh                # Run quick tests
./comprehensive.sh        # Run full test suite
./comprehensive.sh -v     # Verbose output for debugging
./comprehensive.sh -k     # Keep test directory for inspection
```

### CI/CD

The project uses GitHub Actions for continuous integration:
- Tests run on every push and pull request
- Multi-environment testing (Ubuntu versions, Docker Compose versions, shells)
- Automated releases with version tags
- Daily scheduled tests to catch regressions

See [.github/CI.md](.github/CI.md) for detailed CI documentation.

### Writing Tests

When updating BranchBox, ensure tests pass:
1. Test names should use hyphens, not spaces (e.g., `"setup-script"` not `"Setup Script"`)
2. Git-ignored files (like `.env`) won't be cloned - create them in tests if needed
3. Commit any test files that need to be in the repository
4. Run `./check.sh` before pushing to catch issues early

## Troubleshooting

**Port conflicts?** See [DOCKER_SETUP.md](DOCKER_SETUP.md)

**Clean up Docker resources:**
```bash
branchbox remove old-feature
docker system prune -a --volumes
```

## License

MIT
