# BranchBox

[![Tests](https://github.com/dalberto/branchbox/actions/workflows/badge.yml/badge.svg)](https://github.com/dalberto/branchbox/actions/workflows/badge.yml)
[![CI](https://github.com/dalberto/branchbox/actions/workflows/ci.yml/badge.svg)](https://github.com/dalberto/branchbox/actions/workflows/ci.yml)

Git worktree management with optional Docker Compose integration for running multiple branches simultaneously.

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

BranchBox is a Git worktree manager that:
- **Creates isolated worktrees** for different branches in separate directories
- **Automatically detects Docker Compose** and enables container isolation when available
- **Works without Docker** - pure Git worktree management for projects without containers
- **Preserves .env files** from main branch (API keys, secrets) when creating new worktrees
- **Shows service status** including actual ports when Docker is available

**Docker Integration (Optional):**
- **Automatic detection** - enables Docker features only when compose files are present
- **Container isolation** per branch via `COMPOSE_PROJECT_NAME`
- **Port conflict handling** - your project manages ports (see [Docker Setup](DOCKER_SETUP.md))

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
branchbox up <name>                      # Start services (if Docker available)
branchbox down <name> [--remove]         # Stop services (if Docker available) 
branchbox status                         # Show all worktrees with Docker status
branchbox remove <name>                  # Remove worktree
branchbox setup [name]                   # Run setup script for main or specified worktree
```

## Docker Support (Optional)

BranchBox automatically detects Docker Compose files and enables container features when available. For projects without Docker, BranchBox works as a pure Git worktree manager.

**For Docker projects:** Your compose files must handle port conflicts when running multiple worktrees simultaneously. See [DOCKER_SETUP.md](DOCKER_SETUP.md) for strategies.

Basic example:
```yaml
services:
  web:
    ports:
      - "8000"  # Let Docker assign random ports, or use env vars
```

## Directory Structure

```
myproject-branchbox/
├── main/              # Main branch
├── feature-auth/      # Feature branch
└── bugfix-api/        # Another branch
```

When Docker is available, BranchBox sets `COMPOSE_PROJECT_NAME=myproject-feature-auth` for container isolation.

## Common Workflows

### Docker Projects
```bash
branchbox create auth
branchbox create new-api
branchbox up auth     # Start containers, shows ports
branchbox up new-api  # Start containers on different ports
branchbox down auth --remove  # Stop and cleanup
```

### Git-Only Projects  
```bash
branchbox create feature-auth
branchbox create bugfix-db
branchbox status      # Shows "git-only" status
# Work directly in directories - no Docker commands needed
cd feature-auth && npm start  # or whatever your project uses
```

### PR Review
```bash
branchbox create pr-123
branchbox up pr-123   # Starts containers if Docker project
# Test the PR in isolated environment...
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
- `BRANCHBOX_DOCKER_ENABLED` - Docker support: auto, true, or false (default: auto)

**Docker Control:**
- `auto` - Enable Docker only when compose files are detected and Docker is available
- `true` - Force Docker features even without compose files (useful for debugging)
- `false` - Disable Docker features entirely (pure Git worktree mode)

## Git-Only Mode

BranchBox works perfectly without Docker! For non-containerized projects, it provides:
- Git worktree creation and management
- Branch isolation in separate directories  
- Environment file copying between worktrees
- Setup script execution
- Status reporting

Example workflow:
```bash
# Clone any Git repository
branchbox clone https://github.com/user/my-app.git

# Create worktrees for different features
branchbox create feature-auth
branchbox create bugfix-db

# Work directly in worktree directories
cd feature-auth
# ... make changes, commit, etc.
```

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
