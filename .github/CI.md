# GitHub Actions CI Documentation

## Overview

BranchBox uses GitHub Actions for continuous integration, testing across multiple environments and ensuring code quality.

## Workflows

### Core CI (`ci.yml`)
- **Triggers:** Push/PR to main branch
- **Jobs:**
  - Quick tests (5 min timeout)
  - Comprehensive tests (10 min timeout)  
  - ShellCheck linting (errors only)
  - ShellCheck style check (optional, non-blocking)
  - Bash syntax validation
  - Installation testing

### Status Badge (`badge.yml`)
- **Purpose:** Simple workflow for README status badges
- **Runs:** Quick tests only

## ShellCheck Configuration

The `.shellcheckrc` file disables certain warnings that are intentional:

- `SC1091` - Not following sourced files
- `SC2181` - Checking exit codes with `$?`
- `SC2155` - Combined declare and assign (style preference)
- `SC2034` - Unused variables (some for documentation)
- `SC2164` - `cd` without `|| exit` (handled by `set -e`)
- `SC2046` - Word splitting (intentional in some cases)
- `SC2154` - Variables from environment

## Local Testing

Run the same checks locally before pushing:

```bash
# Run local checks
./check.sh

# Run tests manually
cd tests
./quick.sh           # Fast smoke tests
./comprehensive.sh   # Full test suite
```

## Dependabot

Configured to update GitHub Actions weekly with automatic PR creation.

## Badge Status

The README displays status badges for:
- Overall tests
- Full CI pipeline
