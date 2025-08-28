#!/bin/bash

# BranchBox Test Suite
# Comprehensive tests with descriptive error messages

set -e
set -o pipefail

# Force unbuffered output for CI environments
export PYTHONUNBUFFERED=1
stty -onlcr 2>/dev/null || true

# Detect CI environment and force line buffering
if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]; then
    exec 2>&1  # Merge stderr into stdout
fi

# Error trap for debugging
trap 'echo "[ERROR] Script failed at line $LINENO with exit code $?"; echo "[ERROR] Last command: ${BASH_COMMAND}"' ERR

# Test configuration
TEST_DIR="/tmp/branchbox-tests-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCHBOX_SCRIPT="$(dirname "$SCRIPT_DIR")/branchbox"
TEST_REPO_NAME="test-repo"
VERBOSE=${VERBOSE:-false}
KEEP_TEST_DIR=${KEEP_TEST_DIR:-false}

# Source test utilities
if [ -f "$SCRIPT_DIR/test-utils.sh" ]; then
    source "$SCRIPT_DIR/test-utils.sh"
else
    echo "[ERROR] test-utils.sh not found at: $SCRIPT_DIR/test-utils.sh"
    exit 1
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Test counters - explicitly initialize
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Store failed test details
FAILED_TEST_DETAILS=()

# Timing
START_TIME=$(date +%s)

# ============================================================================
# Test Framework Functions
# ============================================================================

log() {
    echo -e "$1"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Assert functions with descriptive messages
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [ "$expected" != "$actual" ]; then
        error "$message"
        error "  Expected: '$expected'"
        error "  Actual:   '$actual'"
        return 1
    fi
    return 0
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"
    
    if [ ! -f "$file" ]; then
        error "$message"
        error "  File not found: $file"
        return 1
    fi
    return 0
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist}"
    
    if [ ! -d "$dir" ]; then
        error "$message"
        error "  Directory not found: $dir"
        return 1
    fi
    return 0
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-File should contain pattern}"
    
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        error "$message"
        error "  File: $file"
        error "  Pattern not found: '$pattern'"
        if [ -f "$file" ]; then
            error "  File contents:"
            head -5 "$file" | sed 's/^/    /'
        fi
        return 1
    fi
    return 0
}

assert_command_succeeds() {
    local command="$1"
    local message="${2:-Command should succeed}"
    
    log_verbose "Running: $command"
    if ! eval "$command" > /tmp/test_output_$$ 2>&1; then
        error "$message"
        error "  Command failed: $command"
        error "  Output:"
        cat /tmp/test_output_$$ | head -10 | sed 's/^/    /'
        rm -f /tmp/test_output_$$
        return 1
    fi
    rm -f /tmp/test_output_$$
    return 0
}

assert_command_fails() {
    local command="$1"
    local message="${2:-Command should fail}"
    
    log_verbose "Running (expecting failure): $command"
    if eval "$command" > /tmp/test_output_$$ 2>&1; then
        error "$message"
        error "  Command succeeded unexpectedly: $command"
        rm -f /tmp/test_output_$$
        return 1
    fi
    rm -f /tmp/test_output_$$
    return 0
}

# Test runner
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Use printf for better control and force flush
    printf "${BOLD}Running:${NC} %-35s ... " "$test_name"
    
    # Create isolated test environment
    local test_dir="$TEST_DIR/$test_name"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # Run test in subshell for isolation
    if ( $test_function ) 2>/tmp/test_error_$$; then
        success "PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}FAILED${NC}"
        if [ -s /tmp/test_error_$$ ]; then
            cat /tmp/test_error_$$ | sed 's/^/  /'
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_TEST_DETAILS+=("$test_name")
    fi
    
    rm -f /tmp/test_error_$$
    cd - > /dev/null
}

skip_test() {
    local test_name="$1"
    local reason="$2"
    
    ((TOTAL_TESTS++))
    ((SKIPPED_TESTS++))
    
    echo -e "${BOLD}Skipping:${NC} $test_name ... ${YELLOW}SKIPPED${NC} ($reason)"
}

# ============================================================================
# Setup and Teardown
# ============================================================================

setup_test_environment() {
    info "Setting up test environment in $TEST_DIR"
    
    # Check prerequisites
    if [ ! -f "$BRANCHBOX_SCRIPT" ]; then
        error "branchbox script not found at: $BRANCHBOX_SCRIPT"
        error "Current directory: $(pwd)"
        error "Script directory: $SCRIPT_DIR"
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        error "git is not installed"
        exit 1
    fi
    
    # Check if Docker is available (but don't fail if not - some tests can still run)
    if ! command -v docker &> /dev/null; then
        warn "Docker is not available - some tests may fail"
    fi
    
    # Create test directory
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    # Set environment for tests
    export BRANCHBOX_AUTO_SETUP=false
    export BRANCHBOX_COPY_ENV_FILES=true
    export BRANCHBOX_WORKTREE_SETUP=false
    
    # Set up Git config if not already set (needed in CI)
    git config --global user.email &>/dev/null || git config --global user.email "test@example.com"
    git config --global user.name &>/dev/null || git config --global user.name "Test User"
    
    info "Test environment ready"
}

cleanup_test_environment() {
    if [ "$KEEP_TEST_DIR" = true ]; then
        warn "Test directory preserved at: $TEST_DIR"
    else
        info "Cleaning up test environment"
        cd /
        rm -rf "$TEST_DIR"
    fi
}

# Create a mock git repository
create_test_repo() {
    local repo_name="${1:-test-repo}"
    local repo_dir="$TEST_DIR/repos/$repo_name"
    
    mkdir -p "$repo_dir"
    cd "$repo_dir"
    
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Create initial files
    echo "# $repo_name" > README.md
    cat > .gitignore << 'EOF'
node_modules/
.env
*.env
EOF
    echo "SECRET_KEY=test123" > .env
    
    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080"
EOF
    
    git add README.md .gitignore docker-compose.yml
    git commit -m "Initial commit" --quiet
    
    echo "$repo_dir"
}

# Create a setup script in repo
create_setup_script() {
    local repo_dir="$1"
    local script_name="${2:-.branchbox-setup.sh}"
    
    cat > "$repo_dir/$script_name" << 'EOF'
#!/bin/bash
echo "Setup running for: $BRANCHBOX_WORKTREE_NAME"
echo "Project: $BRANCHBOX_PROJECT_NAME"
echo "Is main: $BRANCHBOX_IS_MAIN"
touch .setup-completed
EOF
    
    chmod +x "$repo_dir/$script_name"
}

# ============================================================================
# Test Cases
# ============================================================================

# Test: Basic clone functionality
test_clone_basic() {
    local repo_dir=$(create_test_repo "clone-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    # Check directory structure
    assert_dir_exists "clone-test-branchbox" \
        "Worktrees directory should be created"
    assert_dir_exists "clone-test-branchbox/main" \
        "Main worktree should be created"
    
    # Check marker files
    assert_file_exists "clone-test-branchbox/.branchbox" \
        "Root marker file should exist"
    assert_file_contains "clone-test-branchbox/.branchbox" "clone-test" \
        "Root marker should contain project name"
    assert_file_exists "clone-test-branchbox/main/.branchbox-worktree" \
        "Worktree marker should exist in main"
    assert_file_contains "clone-test-branchbox/main/.branchbox-worktree" "main" \
        "Worktree marker should contain 'main'"
    
    # Check git structure (worktrees have .git as a file, not directory)
    if [ ! -e "clone-test-branchbox/main/.git" ]; then
        error "Main should be a git repository"
        error "  .git not found in clone-test-branchbox/main/"
        return 1
    fi
}

# Test: Clone with existing directory
test_clone_existing_directory() {
    local repo_dir=$(create_test_repo "existing-test")
    
    cd "$TEST_DIR"
    mkdir -p "existing-test-branchbox"
    
    assert_command_fails "$BRANCHBOX_SCRIPT clone '$repo_dir' --no-setup 2>&1" \
        "Clone should fail when directory exists"
}

# Test: Create worktree
test_create_worktree() {
    local repo_dir=$(create_test_repo "create-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "create-test-branchbox"
    $BRANCHBOX_SCRIPT create feature-test >/dev/null 2>&1 || true
    
    sleep 1
    
    # Check worktree creation
    assert_dir_exists "feature-test" \
        "Feature worktree directory should exist"
    assert_file_exists "feature-test/.branchbox-worktree" \
        "Worktree marker should exist"
    assert_file_contains "feature-test/.branchbox-worktree" "feature-test" \
        "Worktree marker should contain worktree name"
    
    # Check git branch
    cd feature-test
    local branch=$(git branch --show-current)
    assert_equals "feature-test" "$branch" \
        "Git branch should match worktree name"
}

# Test: Create worktree with different branch name
test_create_worktree_custom_branch() {
    local repo_dir=$(create_test_repo "branch-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "branch-test-branchbox"
    $BRANCHBOX_SCRIPT create my-feature feature/auth >/dev/null 2>&1 || true
    
    sleep 1
    
    assert_dir_exists "my-feature" \
        "Worktree directory should use specified name"
    
    cd my-feature
    local branch=$(git branch --show-current)
    assert_equals "feature/auth" "$branch" \
        "Git branch should use specified branch name"
}

# Test: Directory awareness - run from root
test_directory_awareness_root() {
    local repo_dir=$(create_test_repo "dir-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "dir-test-branchbox"
    local output=$(BRANCHBOX_AUTO_SETUP=false $BRANCHBOX_SCRIPT status 2>&1)
    
    assert_equals "0" "$?" "Status should work from root directory"
    echo "$output" | grep -q "Project: dir-test" || \
        (error "Status output should show project name" && return 1)
}

# Test: Directory awareness - run from worktree
test_directory_awareness_worktree() {
    local repo_dir=$(create_test_repo "worktree-dir-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "worktree-dir-test-branchbox"
    $BRANCHBOX_SCRIPT create feature1 >/dev/null 2>&1
    
    cd feature1
    local output=$($BRANCHBOX_SCRIPT status 2>&1)
    
    assert_equals "0" "$?" "Status should work from within worktree"
    echo "$output" | grep -q "Project: worktree-dir-test" || \
        (error "Status output should show project name from worktree" && return 1)
}

# Test: Directory awareness - run from nested directory
test_directory_awareness_nested() {
    local repo_dir=$(create_test_repo "nested-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "nested-test-branchbox/main"
    mkdir -p deeply/nested/directory
    cd deeply/nested/directory
    
    local output=$($BRANCHBOX_SCRIPT status 2>&1)
    
    assert_equals "0" "$?" "Status should work from deeply nested directory"
    echo "$output" | grep -q "Project: nested-test" || \
        (error "Status output should show project name from nested dir" && return 1)
}

# Test: Setup script execution
test_setup_script() {
    local repo_dir=$(create_test_repo "setup-test")
    create_setup_script "$repo_dir"
    
    # Need to commit the setup script
    cd "$repo_dir"
    git add .branchbox-setup.sh
    git commit -m "Add setup script" --quiet
    
    log_verbose "Test repo created at: $repo_dir"
    log_verbose "Current dir: $(pwd)"
    
    cd "$TEST_DIR"
    
    log_verbose "Changed to TEST_DIR: $(pwd)"
    
    # Test with AUTO_SETUP=true
    local output=$(BRANCHBOX_AUTO_SETUP=true $BRANCHBOX_SCRIPT clone "$repo_dir" 2>&1)
    
    log_verbose "Clone output: $output"
    
    # Give setup script time to complete
    sleep 1
    
    log_verbose "Looking for: setup-test-branchbox/main/.setup-completed"
    log_verbose "Directory contents: $(ls -la 2>&1)"
    
    # Check if setup ran by looking for the marker file
    assert_file_exists "setup-test-branchbox/main/.setup-completed" \
        "Setup script should have run and created marker file"
}

# Test: Setup script with worktree
test_setup_worktree() {
    local repo_dir=$(create_test_repo "worktree-setup")
    create_setup_script "$repo_dir"
    
    # Need to commit the setup script
    cd "$repo_dir"
    git add .branchbox-setup.sh
    git commit -m "Add setup script" --quiet
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "worktree-setup-branchbox"
    local output=$(BRANCHBOX_WORKTREE_SETUP=true $BRANCHBOX_SCRIPT create feature-setup 2>&1)
    
    # Give setup script more time to complete
    sleep 1
    
    assert_file_exists "feature-setup/.setup-completed" \
        "Setup script should run in new worktree when WORKTREE_SETUP=true"
}

# Test: Environment file copying
test_env_file_copy() {
    local repo_dir=$(create_test_repo "env-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "env-test-branchbox"
    # The .env file exists in source but isn't cloned (git-ignored)
    # So we need to manually create it in main first
    echo "SECRET_KEY=test123" > main/.env
    
    BRANCHBOX_COPY_ENV_FILES=true $BRANCHBOX_SCRIPT create feature-env >/dev/null 2>&1
    
    assert_file_exists "feature-env/.env" \
        "Environment file should be copied to new worktree"
    assert_file_contains "feature-env/.env" "SECRET_KEY=test123" \
        "Environment file should contain correct content"
}

# Test: No env file copy when disabled
test_env_file_no_copy() {
    local repo_dir=$(create_test_repo "no-env-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "no-env-test-branchbox"
    BRANCHBOX_COPY_ENV_FILES=false $BRANCHBOX_SCRIPT create feature-noenv >/dev/null 2>&1
    
    if [ -f "feature-noenv/.env" ]; then
        error "Environment file should NOT be copied when COPY_ENV_FILES=false"
        return 1
    fi
}

# Test: Remove worktree
test_remove_worktree() {
    local repo_dir=$(create_test_repo "remove-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "remove-test-branchbox"
    $BRANCHBOX_SCRIPT create feature-remove >/dev/null 2>&1
    
    assert_dir_exists "feature-remove" \
        "Worktree should exist before removal"
    
    assert_command_succeeds "$BRANCHBOX_SCRIPT remove feature-remove" \
        "Remove command should succeed"
    
    if [ -d "feature-remove" ]; then
        error "Worktree directory should be removed"
        return 1
    fi
    
    # Check git worktree list
    cd main
    local worktrees=$(git worktree list | grep "feature-remove" || true)
    if [ -n "$worktrees" ]; then
        error "Git worktree should be removed from git worktree list"
        return 1
    fi
}

# Test: Remove entire project - confirm with yes
test_remove_project_confirmed() {
    local repo_dir=$(create_test_repo "remove-project-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "remove-project-test-branchbox"
    $BRANCHBOX_SCRIPT create feature1 >/dev/null 2>&1 || true
    $BRANCHBOX_SCRIPT create feature2 >/dev/null 2>&1
    
    # Verify project exists before removal
    assert_dir_exists "$TEST_DIR/remove-project-test-branchbox" \
        "Project directory should exist before removal"
    assert_dir_exists "$TEST_DIR/remove-project-test-branchbox/main" \
        "Main worktree should exist"
    assert_dir_exists "$TEST_DIR/remove-project-test-branchbox/feature1" \
        "Feature1 worktree should exist"
    assert_dir_exists "$TEST_DIR/remove-project-test-branchbox/feature2" \
        "Feature2 worktree should exist"
    
    # Run remove-project with "yes" confirmation
    cd "$TEST_DIR/remove-project-test-branchbox"
    echo "yes" | $BRANCHBOX_SCRIPT remove-project >/dev/null 2>&1
    
    # Check that entire project directory is removed
    if [ -d "$TEST_DIR/remove-project-test-branchbox" ]; then
        error "Project directory should be completely removed"
        return 1
    fi
}

# Test: Remove entire project - abort with no
test_remove_project_aborted() {
    local repo_dir=$(create_test_repo "remove-abort-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "remove-abort-test-branchbox"
    $BRANCHBOX_SCRIPT create feature-abort >/dev/null 2>&1
    
    # Run remove-project with "no" confirmation
    echo "no" | $BRANCHBOX_SCRIPT remove-project >/dev/null 2>&1
    
    # Check that project directory still exists
    assert_dir_exists "$TEST_DIR/remove-abort-test-branchbox" \
        "Project directory should still exist after aborting"
    assert_dir_exists "$TEST_DIR/remove-abort-test-branchbox/main" \
        "Main worktree should still exist"
    assert_dir_exists "$TEST_DIR/remove-abort-test-branchbox/feature-abort" \
        "Feature worktree should still exist"
}

# Test: Remove project from within worktree
test_remove_project_from_worktree() {
    local repo_dir=$(create_test_repo "remove-from-worktree")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "remove-from-worktree-branchbox"
    $BRANCHBOX_SCRIPT create feature-nested >/dev/null 2>&1
    
    # Navigate to worktree and try remove-project
    cd feature-nested
    echo "yes" | $BRANCHBOX_SCRIPT remove-project >/dev/null 2>&1
    
    # Check that entire project directory is removed
    if [ -d "$TEST_DIR/remove-from-worktree-branchbox" ]; then
        error "Project directory should be removed even when command run from within worktree"
        return 1
    fi
}

# Test: Status command output
test_status_output() {
    local repo_dir=$(create_test_repo "status-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "status-test-branchbox"
    $BRANCHBOX_SCRIPT create feature1 >/dev/null 2>&1
    $BRANCHBOX_SCRIPT create feature2 >/dev/null 2>&1
    
    local output=$($BRANCHBOX_SCRIPT status)
    
    # Check for expected content
    echo "$output" | grep -q "Project: status-test" || \
        (error "Status should show project name" && return 1)
    echo "$output" | grep -q "main" || \
        (error "Status should show main worktree" && return 1)
    echo "$output" | grep -q "feature1" || \
        (error "Status should show feature1 worktree" && return 1)
    echo "$output" | grep -q "feature2" || \
        (error "Status should show feature2 worktree" && return 1)
}

# Test: Invalid project name
test_invalid_project_name() {
    cd "$TEST_DIR"
    
    assert_command_fails "$BRANCHBOX_SCRIPT clone 'http://example.com/test@repo.git' --no-setup 2>&1" \
        "Clone should fail with invalid project name containing @"
}

# Test: Duplicate worktree name
test_duplicate_worktree() {
    local repo_dir=$(create_test_repo "duplicate-test")
    
    cd "$TEST_DIR"
    $BRANCHBOX_SCRIPT clone "$repo_dir" --no-setup >/dev/null 2>&1
    
    cd "duplicate-test-branchbox"
    $BRANCHBOX_SCRIPT create feature-dup >/dev/null 2>&1
    
    assert_command_fails "$BRANCHBOX_SCRIPT create feature-dup 2>&1" \
        "Creating duplicate worktree should fail"
}

# Test: Help command
test_help_output() {
    local output=$($BRANCHBOX_SCRIPT --help 2>&1 || true)
    
    # Check for essential help content
    echo "$output" | grep -q "Usage:" || \
        (error "Help should show usage" && return 1)
    echo "$output" | grep -q "clone" || \
        (error "Help should mention clone command" && return 1)
    echo "$output" | grep -q "create" || \
        (error "Help should mention create command" && return 1)
    echo "$output" | grep -q "status" || \
        (error "Help should mention status command" && return 1)
    echo "$output" | grep -q "remove-project" || \
        (error "Help should mention remove-project command" && return 1)
}


# ============================================================================
# Test Runner
# ============================================================================

print_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    echo ""
    echo "========================================================================================="
    echo -e "${BOLD}Test Summary${NC}"
    echo "========================================================================================="
    echo -e "Total Tests:    ${BOLD}$TOTAL_TESTS${NC}"
    echo -e "Passed:         ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:         ${RED}$FAILED_TESTS${NC}"
    echo -e "Skipped:        ${YELLOW}$SKIPPED_TESTS${NC}"
    echo -e "Duration:       ${BLUE}${duration}s${NC}"
    echo ""
    
    if [ ${#FAILED_TEST_DETAILS[@]} -gt 0 ]; then
        echo -e "${RED}Failed Tests:${NC}"
        for test_name in "${FAILED_TEST_DETAILS[@]}"; do
            echo "  - $test_name"
        done
        echo ""
    fi
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}✗ Some tests failed${NC}"
        return 1
    fi
}

main() {
    echo "========================================================================================="
    echo -e "${BOLD}BranchBox Test Suite${NC}"
    echo "========================================================================================="
    echo ""
    
    # Setup
    setup_test_environment
    
    # Core functionality tests
    echo ""
    echo -e "${BOLD}${MAGENTA}Core Functionality Tests${NC}"
    echo "------------------------"
    # Force output flush in CI
    printf "" 
    run_test "clone-basic" test_clone_basic
    run_test "clone-existing-directory" test_clone_existing_directory
    run_test "create-worktree" test_create_worktree
    run_test "create-worktree-custom-branch" test_create_worktree_custom_branch
    run_test "remove-worktree" test_remove_worktree
    run_test "remove-project-confirmed" test_remove_project_confirmed
    run_test "remove-project-aborted" test_remove_project_aborted
    run_test "remove-project-from-worktree" test_remove_project_from_worktree
    
    # Directory awareness tests
    echo ""
    echo -e "${BOLD}${MAGENTA}Directory Awareness Tests${NC}"
    echo "-------------------------"
    printf "" # Force flush
    run_test "directory-awareness-root" test_directory_awareness_root
    run_test "directory-awareness-worktree" test_directory_awareness_worktree
    run_test "directory-awareness-nested" test_directory_awareness_nested
    
    # Setup script tests
    echo ""
    echo -e "${BOLD}${MAGENTA}Setup Script Tests${NC}"
    echo "------------------"
    printf "" # Force flush
    run_test "setup-script" test_setup_script
    run_test "setup-worktree" test_setup_worktree
    
    # Environment file tests
    echo ""
    echo -e "${BOLD}${MAGENTA}Environment File Tests${NC}"
    echo "----------------------"
    printf "" # Force flush
    run_test "env-file-copy" test_env_file_copy
    run_test "env-file-no-copy" test_env_file_no_copy
    
    # Status and help tests
    echo ""
    echo -e "${BOLD}${MAGENTA}Command Tests${NC}"
    echo "-------------"
    printf "" # Force flush
    run_test "status-output" test_status_output
    run_test "help-output" test_help_output
    
    # Error handling tests
    echo ""
    echo -e "${BOLD}${MAGENTA}Error Handling Tests${NC}"
    echo "--------------------"
    printf "" # Force flush
    run_test "invalid-project-name" test_invalid_project_name
    run_test "duplicate-worktree" test_duplicate_worktree
    
    # Cleanup
    cleanup_test_environment
    
    # Summary
    print_summary
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -k|--keep)
            KEEP_TEST_DIR=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed test output"
            echo "  -k, --keep       Keep test directory after completion"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

# Run tests
main
exit $?
