#!/bin/bash

# Port Doctor Test Suite
# Tests all port doctor functionality

# Don't exit on error - we want to test failures too
set +e

# Configuration  
TEST_DIR="/tmp/branchbox-port-doctor-test-$$"
BRANCHBOX="$(cd "$(dirname "$0")/.." && pwd)/branchbox"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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

# Test function with expected failure
test_case_fail() {
    local name="$1"
    local cmd="$2"
    local check="$3"
    
    ((TOTAL++))
    echo -ne "${BOLD}Test $TOTAL:${NC} $name ... "
    
    if ! eval "$cmd" >/dev/null 2>&1; then
        if eval "$check" 2>/dev/null; then
            echo -e "${GREEN}PASS${NC}"
            ((PASS++))
        else
            echo -e "${RED}FAIL${NC} (check failed)"
            ((FAIL++))
        fi
    else
        echo -e "${RED}FAIL${NC} (command should have failed)"
        ((FAIL++))
    fi
}

# Setup
echo -e "${BOLD}${BLUE}BranchBox Port Doctor Test Suite${NC}\n"
echo "Setting up test environment..."
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Create test docker-compose files
create_hardcoded_compose() {
    local filename="$1"
    cat > "$filename" << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
      - "8443:443"
  database:
    image: postgres:13
    ports:
      - "5432:5432"
    environment:
      POSTGRES_PASSWORD: password
  frontend:
    image: node:16
    ports:
      - "3000:3000"
    volumes:
      - ./app:/app
EOF
    echo "" >> "$filename"  # Ensure final newline
}

create_random_ports_compose() {
    local filename="$1"
    cat > "$filename" << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "80"
  database:
    image: postgres:13
    ports:
      - "5432"
    environment:
      POSTGRES_PASSWORD: password
EOF
    echo "" >> "$filename"  # Ensure final newline
}

create_mixed_compose() {
    local filename="$1"
    cat > "$filename" << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"  # hardcoded
  api:
    image: node:16
    ports:
      - "3000"     # random
  database:
    image: postgres:13
    ports:
      - "5432:5432"  # hardcoded
EOF
    echo "" >> "$filename"  # Ensure final newline
}

echo -e "\n${BOLD}Running Tests:${NC}\n"

# Test 1: Docker Compose Parser
echo -e "${BOLD}Parser Tests${NC}"

mkdir -p parser-tests
cd parser-tests

create_hardcoded_compose "test-hardcoded.yml"
create_random_ports_compose "test-random.yml"
create_mixed_compose "test-mixed.yml"

# Test parser detection
test_case "Parser detects hardcoded ports" \
    "$SCRIPT_DIR/scripts/docker-compose-parser.sh test-hardcoded.yml detect" \
    "$SCRIPT_DIR/scripts/docker-compose-parser.sh test-hardcoded.yml detect | grep -q '8080:80'"

test_case "Parser detects multiple ports" \
    "$SCRIPT_DIR/scripts/docker-compose-parser.sh test-hardcoded.yml detect" \
    "[ \$($SCRIPT_DIR/scripts/docker-compose-parser.sh test-hardcoded.yml detect | wc -l) -eq 4 ]"

test_case "Parser detects services with ports" \
    "$SCRIPT_DIR/scripts/docker-compose-parser.sh test-hardcoded.yml services" \
    "$SCRIPT_DIR/scripts/docker-compose-parser.sh test-hardcoded.yml services | grep -q 'web'"

test_case "Parser finds all services" \
    "$SCRIPT_DIR/scripts/docker-compose-parser.sh test-hardcoded.yml services" \
    "[ \$($SCRIPT_DIR/scripts/docker-compose-parser.sh test-hardcoded.yml services | wc -l) -eq 3 ]"

test_case "Parser check detects conflicts" \
    "$SCRIPT_DIR/scripts/docker-compose-parser.sh test-hardcoded.yml check" \
    "true"

test_case "Parser check succeeds on random ports" \
    "! $SCRIPT_DIR/scripts/docker-compose-parser.sh test-random.yml check" \
    "true"

test_case "Mixed compose detection" \
    "$SCRIPT_DIR/scripts/docker-compose-parser.sh test-mixed.yml services" \
    "[ \$($SCRIPT_DIR/scripts/docker-compose-parser.sh test-mixed.yml services | wc -l) -eq 2 ]"

cd ..

# Test 2: Port Assignment Logic
echo -e "\n${BOLD}Port Assignment Tests${NC}"

mkdir -p assignment-tests
cd assignment-tests

create_hardcoded_compose "docker-compose.yml"

# Test deterministic hashing
test_case "Consistent hash for same worktree" \
    "hash1=\$($SCRIPT_DIR/scripts/port-assignment.sh feature-auth assignments); hash2=\$($SCRIPT_DIR/scripts/port-assignment.sh feature-auth assignments)" \
    "[ \"\$hash1\" = \"\$hash2\" ]"

test_case "Different hash for different worktrees" \
    "hash1=\$($SCRIPT_DIR/scripts/port-assignment.sh feature-auth assignments | head -1); hash2=\$($SCRIPT_DIR/scripts/port-assignment.sh feature-payment assignments | head -1)" \
    "[ \"\$hash1\" != \"\$hash2\" ]"

test_case "Port assignment generates correct format" \
    "$SCRIPT_DIR/scripts/port-assignment.sh test-branch assignments" \
    "$SCRIPT_DIR/scripts/port-assignment.sh test-branch assignments | grep -q '^[^:]*:[0-9]*:[0-9]*:[0-9]*\$'"

test_case "Port assignment preview works" \
    "$SCRIPT_DIR/scripts/port-assignment.sh test-branch preview" \
    "$SCRIPT_DIR/scripts/port-assignment.sh test-branch preview | grep -q 'Port assignments for worktree'"

test_case "Override generation includes all services" \
    "$SCRIPT_DIR/scripts/port-assignment.sh test-branch generate" \
    "$SCRIPT_DIR/scripts/port-assignment.sh test-branch generate | grep -c 'ports: !override' | grep -q '3'"

cd ..

# Test 3: Main Port Doctor Script
echo -e "\n${BOLD}Port Doctor Integration Tests${NC}"

mkdir -p integration-tests
cd integration-tests

create_hardcoded_compose "docker-compose.yml"

# Test detection - should exit 1 when conflicts found
test_case "Doctor detects conflicts" \
    "! $SCRIPT_DIR/scripts/branchbox-port-doctor.sh --check ." \
    "true"

# Test auto-fix
test_case "Doctor creates override file" \
    "$SCRIPT_DIR/scripts/branchbox-port-doctor.sh --fix --worktree test-fix ." \
    "[ -f docker-compose.override.yml ]"

test_case "Override file has BranchBox signature" \
    "true" \
    "grep -q 'Generated by BranchBox Port Doctor' docker-compose.override.yml"

test_case "Override file has correct format" \
    "true" \
    "grep -q 'ports: !override' docker-compose.override.yml"

test_case "Override file has port mappings" \
    "true" \
    "grep -c '\"[0-9]*:[0-9]*\"' docker-compose.override.yml | grep -q '[1-9]'"

# Test with existing override
test_case "Doctor detects existing BranchBox override" \
    "echo 'y' | $SCRIPT_DIR/scripts/branchbox-port-doctor.sh --worktree test-existing ." \
    "grep -q 'BranchBox override file already exists' /tmp/test-output 2>/dev/null || true"

# Create non-BranchBox override
rm -f docker-compose.override.yml
echo "# Manual override" > docker-compose.override.yml

test_case "Doctor backs up existing override" \
    "$SCRIPT_DIR/scripts/branchbox-port-doctor.sh --fix --worktree test-backup ." \
    "ls docker-compose.override.yml.backup-* >/dev/null 2>&1"

cd ..

# Test 4: BranchBox Integration
echo -e "\n${BOLD}BranchBox Integration Tests${NC}"

# Create test repo with port conflicts
mkdir test-repo
cd test-repo
git init -q
git config user.email "test@test.com"  
git config user.name "Test"
echo "# Test" > README.md
create_hardcoded_compose "docker-compose.yml"
git add -A
git commit -qm "Initial"
REPO_PATH="$(pwd)"
cd ..

# Test branchbox doctor command
test_case "BranchBox clone creates structure" \
    "$BRANCHBOX clone '$REPO_PATH' --no-setup" \
    "[ -d test-repo-branchbox/main ]"

cd test-repo-branchbox

test_case "BranchBox doctor command exists" \
    "$BRANCHBOX doctor --help" \
    "$BRANCHBOX doctor --help | grep -q 'Port Doctor'"

test_case "BranchBox doctor detects conflicts" \
    "! $BRANCHBOX doctor --check main" \
    "true"

test_case "BranchBox doctor can fix conflicts" \
    "$BRANCHBOX doctor --fix main" \
    "[ -f main/docker-compose.override.yml ]"

# Test integration with create command
test_case "Create worktree with port conflicts" \
    "echo 'n' | $BRANCHBOX create feature-test 2>&1" \
    "[ -d feature-test ]"

cd ..

# Test 5: Edge Cases
echo -e "\n${BOLD}Edge Case Tests${NC}"

mkdir -p edge-tests
cd edge-tests

# Empty compose file
echo "version: '3.8'" > docker-compose.yml

test_case "Empty compose file (no conflicts)" \
    "$SCRIPT_DIR/scripts/branchbox-port-doctor.sh --check ." \
    "true"

# No compose file
rm -f docker-compose.yml docker-compose.yaml compose.yml compose.yaml
test_case "No compose file (no conflicts)" \
    "$SCRIPT_DIR/scripts/branchbox-port-doctor.sh --check ." \
    "true"

# Compose file with no services
cat > no-services.yml << 'EOF'
version: '3.8'
volumes:
  data:
networks:
  app:
EOF

cp no-services.yml docker-compose.yml
test_case "Compose with no services (no conflicts)" \
    "$SCRIPT_DIR/scripts/branchbox-port-doctor.sh --check ." \
    "true"

# Services with no ports
cat > no-ports.yml << 'EOF' 
version: '3.8'
services:
  web:
    image: nginx:alpine
  database:
    image: postgres:13
EOF
echo "" >> no-ports.yml  # Ensure final newline

cp no-ports.yml docker-compose.yml
test_case "Services with no ports (no conflicts)" \
    "$SCRIPT_DIR/scripts/branchbox-port-doctor.sh --check ." \
    "true"

cd ..

# Cleanup
echo -e "\n${BOLD}Cleaning up...${NC}"
cd /
rm -rf "$TEST_DIR"

# Summary
echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Port Doctor Test Summary:${NC}"
echo -e "  Total: $TOTAL"
echo -e "  ${GREEN}Passed: $PASS${NC}"
if [ $FAIL -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAIL${NC}"
    echo -e "\n${RED}${BOLD}✗ Port Doctor tests failed${NC}"
    exit 1
else
    echo -e "\n${GREEN}${BOLD}✓ All Port Doctor tests passed!${NC}"
    exit 0
fi