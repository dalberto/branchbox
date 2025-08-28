#!/bin/bash

# Local checking script for BranchBox
# Runs the same checks as CI locally

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BOLD}BranchBox Local Check Script${NC}\n"

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
    echo -e "${YELLOW}Warning: ShellCheck not installed${NC}"
    echo "Install with: brew install shellcheck (macOS) or apt-get install shellcheck (Linux)"
    echo ""
fi

# Syntax check
echo -e "${BOLD}Running syntax checks...${NC}"
for file in branchbox install.sh tests/*.sh; do
    if bash -n "$file" 2>/dev/null; then
        echo -e "  ✓ $file"
    else
        echo -e "  ${RED}✗ $file${NC}"
        exit 1
    fi
done
echo ""

# ShellCheck if available
if command -v shellcheck &> /dev/null; then
    echo -e "${BOLD}Running ShellCheck...${NC}"
    if shellcheck branchbox install.sh tests/*.sh; then
        echo -e "${GREEN}✓ All checks passed${NC}"
    else
        echo -e "${RED}✗ ShellCheck found issues${NC}"
        echo -e "${YELLOW}Note: Some warnings are suppressed via .shellcheckrc${NC}"
    fi
else
    echo -e "${YELLOW}Skipping ShellCheck (not installed)${NC}"
fi
echo ""

# Quick test
echo -e "${BOLD}Run quick tests? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    cd tests
    ./quick.sh
fi