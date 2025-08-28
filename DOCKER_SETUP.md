# Docker Setup Guide for BranchBox

## Prerequisites

Before creating worktrees, ensure your main repository is properly configured:

1. Set up secrets, API keys, and environment variables
2. Verify `docker-compose.yml` works correctly
3. Test that all services start without errors
4. Optionally create a setup script (`setup.sh`, `init.sh`, `bootstrap.sh`, or `.branchbox-setup.sh`) for automated initialization

## How BranchBox Handles Docker

BranchBox automatically sets `COMPOSE_PROJECT_NAME` for each worktree, ensuring complete isolation of containers, networks, and volumes between worktrees. You don't need to configure this—it just works.

The main challenge you need to solve is **port conflicts** when running multiple worktrees simultaneously.

## Port Management Strategies

### Strategy 1: Random Port Assignment (Simplest)

Let Docker automatically assign random available ports:

```yaml
# docker-compose.yml
services:
  web:
    ports:
      - "8000"  # Expose container port 8000 on random host port
  
  database:
    ports:
      - "5432"  # Expose container port 5432 on random host port
  
  frontend:
    ports:
      - "3000"  # Expose container port 3000 on random host port
```

To find the assigned ports:
```bash
docker compose port web 8000      # Shows actual host port for web service
docker compose port database 5432  # Shows actual host port for database
```

**Pros:** Zero configuration required  
**Cons:** Ports change on each restart; requires port lookup

### Strategy 2: Override File with Random Ports

Create a `docker-compose.override.yml` file that lets Docker assign random ports:

```yaml
# docker-compose.override.yml
# Requires Docker Compose v2.20.0+ for !override syntax
services:
  web:
    ports: !override
      - "8000"  # Expose container port 8000 on random host port
  
  database:
    ports: !override
      - "5432"  # Expose container port 5432 on random host port
  
  frontend:
    ports: !override
      - "3000"  # Expose container port 3000 on random host port
```

You have two options:
- **Check it in**: Each branch gets its own override file with random ports
- **Add to .gitignore**: Create manually in each worktree

**Pros:** Simple configuration file approach; can be version controlled if desired  
**Cons:** Still requires port lookup; manual creation for each worktree if not checked in

### Strategy 3: Automated Port Assignment with Git Hooks

Automatically generate random ports for each worktree using git hooks.

#### Step 1: Prepare docker-compose.yml

Use environment variables with defaults:

```yaml
# docker-compose.yml
services:
  web:
    ports:
      - "${APP_PORT:-8000}:8000"
  
  database:
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
  
  frontend:
    ports:
      - "${FRONTEND_PORT:-3000}:3000"
```

#### Step 2: Create Port Generation Script

Create `scripts/generate-worktree-ports.sh`:

```bash
#!/bin/bash

if [[ $(git rev-parse --git-common-dir 2>/dev/null) != ".git" ]]; then
  # In a worktree - create override file with random ports in familiar ranges
  cat > docker-compose.override.yml << EOF
# Auto-generated for worktree - DO NOT COMMIT
# Generated at: $(date)
# Requires Docker Compose v2.20.0+
services:
  web:
    ports: !override
      - "$((RANDOM % 1000 + 8000)):8000"  # Random port 8000-8999
  
  database:
    ports: !override
      - "$((RANDOM % 1000 + 5432)):5432"  # Random port 5432-6431
  
  frontend:
    ports: !override
      - "$((RANDOM % 1000 + 3000)):3000"  # Random port 3000-3999
EOF
  echo "✅ Created docker-compose.override.yml with randomized ports for worktree"
else
  # In main repo - remove override file
  if [[ -f docker-compose.override.yml ]]; then
    rm -f docker-compose.override.yml
    echo "🧹 Removed docker-compose.override.yml (not needed in main repo)"
  fi
fi
```

Make it executable: `chmod +x scripts/generate-worktree-ports.sh`

#### Step 3: Set Up Git Hook

**Option A: Local Git Hook**

Create `.git/hooks/post-checkout`:

```bash
#!/bin/bash
./scripts/generate-worktree-ports.sh
```

Make it executable: `chmod +x .git/hooks/post-checkout`

**Option B: Team-Wide with Lefthook (Optional)**

If your team uses [Lefthook](https://github.com/evilmartians/lefthook) for shared git hooks:

```yaml
# lefthook.yml
post-checkout:
  commands:
    generate-worktree-ports:
      run: ./scripts/generate-worktree-ports.sh
```

Then team members run `lefthook install` once to set up hooks.

#### Step 4: Update .gitignore

Add to `.gitignore` (since these are auto-generated per worktree):

```
docker-compose.override.yml
```

**Pros:** Fully automated; ports stay in familiar ranges (8xxx for web, 5xxx for database, 3xxx for frontend)  
**Cons:** Requires initial setup

## Testing Your Setup

1. Create a test worktree:
   ```bash
   git worktree add -b test-branch ../test-worktree
   cd ../test-worktree
   ```

2. Start services:
   ```bash
   docker compose up -d
   ```

3. Verify isolation:
   ```bash
   docker compose ps  # Should only show this worktree's containers
   ```

## Notes

- The `!override` syntax requires Docker Compose v2.20.0 or later. For older versions, omit the `!override` keyword (but be aware this merges arrays instead of replacing them).
- Each worktree's containers are completely isolated thanks to BranchBox's automatic `COMPOSE_PROJECT_NAME` configuration.
- Choose the strategy that best fits your team's workflow—there's no one-size-fits-all solution.