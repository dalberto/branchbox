#!/bin/bash

# Quick BranchBox Test Suite
# Tests core functionality without exec $SHELL issues

# Don't exit on error - we want to test failures too
set +e

# Configuration
TEST_DIR="/tmp/branchbox-quick-test-$$"
BRANCHBOX="$(cd "$(dirname "$0")/.." && pwd)/branchbox"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Counters
TOTAL=0
PASS=0
FAIL=0

# Test function
test_case() {
    local name="$1"
    local cmd="$2"
    local check="$3"
    
    ((TOTAL++))
    echo -ne "${BOLD}Test $TOTAL:${NC} $name ... "
    
    if eval "$cmd" >/dev/null 2>&1; then
        if eval "$check" 2>/dev/null; then
            echo -e "${GREEN}PASS${NC}"
            ((PASS++))
        else
            echo -e "${RED}FAIL${NC} (check failed)"
            ((FAIL++))
        fi
    else
        echo -e "${RED}FAIL${NC} (command failed)"
        ((FAIL++))
    fi
}

# Setup
echo -e "${BOLD}${BLUE}BranchBox Quick Test Suite${NC}\n"
echo "Setting up test environment..."
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Create a test repo
echo "Creating test repository..."
mkdir test-repo
cd test-repo
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "# Test" > README.md
echo ".env" > .gitignore
echo "SECRET=123" > .env
cat > docker-compose.yml << 'EOF'
version: '3'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080"
EOF
cat > .branchbox-setup.sh << 'EOF'
#!/bin/bash
echo "Setup: $BRANCHBOX_WORKTREE_NAME"
touch .setup-done
EOF
chmod +x .branchbox-setup.sh
git add -A
git commit -qm "Initial"
REPO_PATH="$(pwd)"
cd ..

echo -e "\n${BOLD}Running Tests:${NC}\n"

# Test 1: Clone with marker files
test_case "Clone creates structure" \
    "$BRANCHBOX clone '$REPO_PATH' --no-setup 2>&1" \
    "[ -d test-repo-branchbox/main ]"

test_case "Root marker exists" \
    "true" \
    "[ -f test-repo-branchbox/.branchbox ]"

test_case "Root marker contains project name" \
    "true" \
    "grep -q 'test-repo' test-repo-branchbox/.branchbox"

test_case "Main worktree marker exists" \
    "true" \
    "[ -f test-repo-branchbox/main/.branchbox-worktree ]"

test_case "Main marker contains 'main'" \
    "true" \
    "grep -q 'main' test-repo-branchbox/main/.branchbox-worktree"

# Test 2: Create worktree
cd test-repo-branchbox
test_case "Create worktree" \
    "$BRANCHBOX create feature1 2>&1" \
    "[ -d feature1 ]"

test_case "Feature worktree marker" \
    "true" \
    "[ -f feature1/.branchbox-worktree ]"

test_case "Feature marker content" \
    "true" \
    "grep -q 'feature1' feature1/.branchbox-worktree"

# Test 3: Directory awareness
test_case "Status from root" \
    "$BRANCHBOX status 2>&1 | grep -q 'test-repo'" \
    "true"

test_case "Status from worktree" \
    "cd main && $BRANCHBOX status 2>&1 | grep -q 'test-repo'" \
    "true"

test_case "Status from nested dir" \
    "mkdir -p main/a/b/c && cd main/a/b/c && $BRANCHBOX status 2>&1 | grep -q 'test-repo'" \
    "true"

cd "$TEST_DIR/test-repo-branchbox"

# Test 4: Environment file copy
# Note: .env files are git-ignored, so they don't get cloned. Create one manually.
echo "SECRET=123" > main/.env
test_case "Env file in main" \
    "[ -f main/.env ]" \
    "true"

test_case "Create with env copy" \
    "BRANCHBOX_COPY_ENV_FILES=true $BRANCHBOX create feature-env 2>&1" \
    "[ -f feature-env/.env ]"

test_case "Env file contents match" \
    "true" \
    "grep -q 'SECRET=123' feature-env/.env"

test_case "Create without env copy" \
    "BRANCHBOX_COPY_ENV_FILES=false $BRANCHBOX create feature-noenv 2>&1" \
    "! [ -f feature-noenv/.env ]"

# Test 5: Setup scripts
test_case "Setup script exists" \
    "[ -f main/.branchbox-setup.sh ]" \
    "true"

test_case "Run setup manually" \
    "$BRANCHBOX setup main 2>&1" \
    "[ -f main/.setup-done ]"

test_case "Setup in new worktree" \
    "BRANCHBOX_WORKTREE_SETUP=true $BRANCHBOX create feature-setup 2>&1 && sleep 1" \
    "[ -f feature-setup/.setup-done ]"

# Test 6: Remove worktree
test_case "Create test worktree" \
    "$BRANCHBOX create to-remove 2>&1" \
    "[ -d to-remove ]"

test_case "Remove worktree" \
    "$BRANCHBOX remove to-remove 2>&1" \
    "! [ -d to-remove ]"

test_case "Git worktree cleaned" \
    "cd main && ! git worktree list | grep -q to-remove" \
    "true"

# Test 7: Duplicate worktree
cd "$TEST_DIR/test-repo-branchbox"
test_case "Create first worktree" \
    "$BRANCHBOX create duplicate 2>&1" \
    "[ -d duplicate ]"

test_case "Duplicate fails" \
    "! $BRANCHBOX create duplicate 2>&1" \
    "true"

# Test 8: Status output
test_case "Status shows all worktrees" \
    "$BRANCHBOX status 2>&1 | grep -c 'main\|feature' | grep -q '[2-9]'" \
    "true"

# Test 9: Help output
test_case "Help shows usage" \
    "$BRANCHBOX --help 2>&1 | grep -q 'Usage'" \
    "true"

test_case "Help shows commands" \
    "$BRANCHBOX --help 2>&1 | grep -q 'clone.*create.*status'" \
    "true"

# Cleanup
echo -e "\n${BOLD}Cleaning up...${NC}"
cd /
rm -rf "$TEST_DIR"

# Summary
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Test Summary:${NC}"
echo -e "  Total: $TOTAL"
echo -e "  ${GREEN}Passed: $PASS${NC}"
if [ $FAIL -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAIL${NC}"
    echo -e "\n${RED}${BOLD}✗ Tests failed${NC}"
    exit 1
else
    echo -e "\n${GREEN}${BOLD}✓ All tests passed!${NC}"
    exit 0
fi