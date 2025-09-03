#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default installation directory
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# GitHub repository details
GITHUB_REPO="dalberto/branchbox"
SCRIPT_NAME="branchbox"

# Installation mode
LOCAL_INSTALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL_INSTALL=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --local    Install from local directory (for development/testing)"
            echo "  --help     Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  INSTALL_DIR    Installation directory (default: ~/.local/bin)"
            echo "  GITHUB_TOKEN   GitHub token for private repo access"
            exit 0
            ;;
        *)
            print_message "$RED" "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if directory is in PATH
is_in_path() {
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Main installation
main() {
    if [ "$LOCAL_INSTALL" = true ]; then
        print_message "$YELLOW" "Installing branchbox from local directory..."
    else
        print_message "$YELLOW" "Installing branchbox from GitHub..."
    fi

    # Create installation directory if it doesn't exist
    if [ ! -d "$INSTALL_DIR" ]; then
        print_message "$YELLOW" "Creating directory: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi

    if [ "$LOCAL_INSTALL" = true ]; then
        # Local installation - copy from current directory
        if [ ! -f "./${SCRIPT_NAME}" ]; then
            print_message "$RED" "Error: ${SCRIPT_NAME} not found in current directory"
            print_message "$YELLOW" "Make sure you run this script from the branchbox repository directory"
            exit 1
        fi
        
        print_message "$GREEN" "Copying local ${SCRIPT_NAME} to ${INSTALL_DIR}..."
        cp "./${SCRIPT_NAME}" "${INSTALL_DIR}/${SCRIPT_NAME}"
        
        # Check if scripts directory exists and copy it
        if [ -d "./scripts" ]; then
            print_message "$GREEN" "Copying scripts directory..."
            # Create scripts directory relative to install location
            local scripts_target="${INSTALL_DIR}/../branchbox-scripts"
            mkdir -p "$scripts_target"
            cp -r "./scripts"/* "$scripts_target/"
            chmod +x "$scripts_target"/*.sh
            
            # Update the branchbox script to use the correct scripts path
            sed -i.bak "s|SCRIPT_PATH=\"\$(cd \"\$(dirname \"\${BASH_SOURCE\[0\]}\")\" \&\& pwd)\"|SCRIPT_PATH=\"${scripts_target%/*}\"|" "${INSTALL_DIR}/${SCRIPT_NAME}"
            rm "${INSTALL_DIR}/${SCRIPT_NAME}.bak"
            
            print_message "$GREEN" "✓ Port Doctor scripts installed to ${scripts_target}"
        fi
        
    else
        # Download from GitHub
        # Try using gh CLI first (if available and authenticated)
        if command -v gh &> /dev/null && gh auth status &> /dev/null; then
            print_message "$GREEN" "Using GitHub CLI to download from private repo..."
            gh api "repos/${GITHUB_REPO}/contents/${SCRIPT_NAME}" \
                --jq '.content' | base64 -d > "${INSTALL_DIR}/${SCRIPT_NAME}"
        # Try using curl with GitHub token
        elif [ -n "$GITHUB_TOKEN" ]; then
            print_message "$GREEN" "Using GitHub token to download from private repo..."
            curl -H "Authorization: token $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github.v3.raw" \
                -L "https://api.github.com/repos/${GITHUB_REPO}/contents/${SCRIPT_NAME}" \
                -o "${INSTALL_DIR}/${SCRIPT_NAME}"
        # Try SSH clone method
        elif ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            print_message "$GREEN" "Using SSH to clone and install..."
            TEMP_DIR=$(mktemp -d)
            git clone --depth 1 "git@github.com:${GITHUB_REPO}.git" "$TEMP_DIR"
            cp "$TEMP_DIR/${SCRIPT_NAME}" "${INSTALL_DIR}/${SCRIPT_NAME}"
            
            # Install scripts if they exist
            if [ -d "$TEMP_DIR/scripts" ]; then
                print_message "$GREEN" "Installing Port Doctor scripts..."
                local scripts_target="${INSTALL_DIR}/../branchbox-scripts"
                mkdir -p "$scripts_target"
                cp -r "$TEMP_DIR/scripts"/* "$scripts_target/"
                chmod +x "$scripts_target"/*.sh
                
                # Update the branchbox script to use the correct scripts path
                sed -i.bak "s|SCRIPT_PATH=\"\$(cd \"\$(dirname \"\${BASH_SOURCE\[0\]}\")\" \&\& pwd)\"|SCRIPT_PATH=\"${scripts_target%/*}\"|" "${INSTALL_DIR}/${SCRIPT_NAME}"
                rm "${INSTALL_DIR}/${SCRIPT_NAME}.bak" 2>/dev/null || true
                
                print_message "$GREEN" "✓ Port Doctor scripts installed to ${scripts_target}"
            fi
            
            rm -rf "$TEMP_DIR"
        else
            print_message "$RED" "Error: Unable to access private repository."
            print_message "$YELLOW" "Please use one of the following methods:"
            echo "  1. Install and authenticate GitHub CLI: gh auth login"
            echo "  2. Set GITHUB_TOKEN environment variable"
            echo "  3. Configure SSH access to GitHub"
            exit 1
        fi
    fi

    # Make the script executable
    chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"

    print_message "$GREEN" "✓ branchbox installed to ${INSTALL_DIR}/${SCRIPT_NAME}"

    # Check if install directory is in PATH
    if ! is_in_path "$INSTALL_DIR"; then
        print_message "$YELLOW" "⚠ Warning: $INSTALL_DIR is not in your PATH"
        echo ""
        echo "Add it to your PATH by adding this line to your shell configuration:"
        echo ""
        if [ -n "$ZSH_VERSION" ]; then
            echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
            echo "  source ~/.zshrc"
        elif [ -n "$BASH_VERSION" ]; then
            echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
            echo "  source ~/.bashrc"
        else
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    else
        print_message "$GREEN" "✓ Installation complete! You can now use 'branchbox' command."
    fi
}

main "$@"
