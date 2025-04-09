#!/bin/bash

set -e

# Color Control Sequences
RESET="\033[0m"
RED="\033[31;1m"
GREEN="\033[32;1m"
YELLOW="\033[33;1m"
BLUE="\033[34;1m"

# Configuration
GITHUB_REPO="build-ongoku/public-releases"
BINARY_NAME="goku"
INSTALL_DIR="/usr/local/bin"
TMP_DIR=$(mktemp -d)
RELEASE_TAG="latest"

echo -e "${BLUE}Installing ${BINARY_NAME}...${RESET}"

# Detect OS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
    "darwin") ;;
    "linux") ;;
    *)
        echo -e "${RED}Unsupported operating system: $OS${RESET}"
        echo -e "${YELLOW}The Goku binary is only available for macOS (darwin) and Linux.${RESET}"
        exit 1
        ;;
esac

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    "x86_64") ARCH="amd64" ;;
    "amd64") ;;
    "arm64") ;;
    "aarch64") ARCH="arm64" ;;
    *)
        echo -e "${RED}Unsupported architecture: $ARCH${RESET}"
        echo -e "${YELLOW}The Goku binary is only available for amd64 and arm64 architectures.${RESET}"
        exit 1
        ;;
esac

echo -e "${YELLOW}Detected system: $OS/$ARCH${RESET}"

# Construct binary name
BINARY_FILE="${BINARY_NAME}.${OS}_${ARCH}"
if [ "$OS" = "windows" ]; then
    BINARY_FILE="${BINARY_FILE}.exe"
fi

# Use direct download URL for public repo
echo -e "${YELLOW}Downloading ${BINARY_NAME} binary for $OS/$ARCH${RESET}"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${BINARY_FILE}"
echo -e "${YELLOW}Downloading from: ${DOWNLOAD_URL}${RESET}"

# Use curl with retry and progress bar
curl -L --retry 3 --retry-delay 1 --progress-bar "$DOWNLOAD_URL" -o "${TMP_DIR}/${BINARY_FILE}"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to download the binary from GitHub.${RESET}"
    echo -e "${YELLOW}This may be because:${RESET}"
    echo -e "${YELLOW}1. The binary doesn't exist for your OS/architecture${RESET}"
    echo -e "${YELLOW}2. The release hasn't been fully published yet${RESET}"
    echo -e "${YELLOW}3. GitHub is experiencing issues${RESET}"
    exit 1
fi

# Make binary executable
chmod +x "${TMP_DIR}/${BINARY_FILE}"

# Install binary
echo -e "${YELLOW}Installing to ${INSTALL_DIR}/${BINARY_NAME}${RESET}"
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Creating directory: ${INSTALL_DIR}${RESET}"
    mkdir -p "$INSTALL_DIR"
fi

# Check if we need sudo to write to INSTALL_DIR
if [ -w "$INSTALL_DIR" ]; then
    mv "${TMP_DIR}/${BINARY_FILE}" "${INSTALL_DIR}/${BINARY_NAME}"
else
    echo -e "${YELLOW}Elevated permissions required to install to ${INSTALL_DIR}${RESET}"
    sudo mv "${TMP_DIR}/${BINARY_FILE}" "${INSTALL_DIR}/${BINARY_NAME}"
fi

# Cleanup
rm -rf "$TMP_DIR"

# Verify installation
if command -v "$BINARY_NAME" &>/dev/null; then
    echo -e "${GREEN}Successfully installed ${BINARY_NAME} to ${INSTALL_DIR}${RESET}"
    echo -e "${YELLOW}You can now run '${BINARY_NAME}' from your terminal.${RESET}"
    
    # Display version information if available
    if $BINARY_NAME version &>/dev/null; then
        echo -e "${YELLOW}Installed version:${RESET}"
        $BINARY_NAME version
    fi
else
    echo -e "${YELLOW}Installation complete, but '$BINARY_NAME' is not in your PATH.${RESET}"
    echo -e "${YELLOW}You can run it using ${INSTALL_DIR}/${BINARY_NAME}${RESET}"
    echo -e "${YELLOW}Consider adding ${INSTALL_DIR} to your PATH.${RESET}"
fi

echo -e "${GREEN}Installation complete!${RESET}"
