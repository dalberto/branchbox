#!/bin/bash

# Test utilities for BranchBox tests
# Provides cross-platform compatibility functions

# Cross-platform timeout function
# Falls back to sleep if timeout command is not available
run_with_timeout() {
    local timeout_seconds="$1"
    shift
    local command="$@"
    
    if command -v timeout &> /dev/null; then
        # Use timeout if available
        timeout "$timeout_seconds" $command
    elif command -v gtimeout &> /dev/null; then
        # macOS with coreutils installed
        gtimeout "$timeout_seconds" $command
    else
        # Fallback: run command with basic timeout using background process
        (
            eval "$command" &
            local pid=$!
            
            # Wait for command or timeout
            local count=0
            while kill -0 $pid 2>/dev/null && [ $count -lt $timeout_seconds ]; do
                sleep 1
                ((count++))
            done
            
            # Kill if still running
            if kill -0 $pid 2>/dev/null; then
                kill -TERM $pid 2>/dev/null
                sleep 0.5
                kill -KILL $pid 2>/dev/null
            fi
            
            wait $pid 2>/dev/null
        )
    fi
}

# Check if running in CI environment
is_ci() {
    [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ] || [ -n "$JENKINS_URL" ] || [ -n "$GITLAB_CI" ]
}

# Get appropriate timeout duration based on environment
get_timeout() {
    local default_timeout="$1"
    if is_ci; then
        # Use longer timeouts in CI
        echo $((default_timeout * 2))
    else
        echo "$default_timeout"
    fi
}