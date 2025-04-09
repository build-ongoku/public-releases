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
ACTUAL_BINARY_NAME="${BINARY_NAME}_actual"
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
echo -e "${YELLOW}Installing actual binary to ${INSTALL_DIR}/${ACTUAL_BINARY_NAME}${RESET}"
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Creating directory: ${INSTALL_DIR}${RESET}"
    # Check if we need sudo to create directory
    if [ -w "$(dirname "$INSTALL_DIR")" ]; then
        mkdir -p "$INSTALL_DIR"
    else
        echo -e "${YELLOW}Elevated permissions required to create ${INSTALL_DIR}${RESET}"
        sudo mkdir -p "$INSTALL_DIR"
    fi
fi

# Check if we need sudo to write to INSTALL_DIR
if [ -w "$INSTALL_DIR" ]; then
    mv "${TMP_DIR}/${BINARY_FILE}" "${INSTALL_DIR}/${ACTUAL_BINARY_NAME}"
else
    echo -e "${YELLOW}Elevated permissions required to install to ${INSTALL_DIR}${RESET}"
    sudo mv "${TMP_DIR}/${BINARY_FILE}" "${INSTALL_DIR}/${ACTUAL_BINARY_NAME}"
fi

# Create wrapper script
echo -e "${YELLOW}Creating update wrapper script at ${INSTALL_DIR}/${BINARY_NAME}${RESET}"

cat > "${TMP_DIR}/${BINARY_NAME}" << 'EOL'
#!/bin/bash

# Configuration
GITHUB_REPO="build-ongoku/public-releases"
BINARY_NAME="goku"
ACTUAL_BINARY_NAME="${BINARY_NAME}_actual"
INSTALL_DIR="/usr/local/bin"
RELEASE_TAG="latest"

# Color Control Sequences
RESET="\033[0m"
GREEN="\033[32;1m"
YELLOW="\033[33;1m"
BLUE="\033[34;1m"

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
    "x86_64") ARCH="amd64" ;;
    "amd64") ;;
    "arm64") ;;
    "aarch64") ARCH="arm64" ;;
    *) ARCH="unsupported" ;;
esac

# Function to check and update if needed
check_and_update() {
    echo -e "${BLUE}Checking for ${BINARY_NAME} updates...${RESET}"
    
    # Skip update check if binary doesn't exist
    if [ ! -f "$INSTALL_DIR/$ACTUAL_BINARY_NAME" ]; then
        echo -e "${YELLOW}No existing installation found. Skipping update check.${RESET}"
        return 1
    fi
    
    # Construct binary name for download
    BINARY_FILE="${BINARY_NAME}.${OS}_${ARCH}"
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${BINARY_FILE}"
    
    # Create temporary directory for work
    TMP_DIR=$(mktemp -d)
    TEMP_BINARY="${TMP_DIR}/${BINARY_FILE}"
    
    # Check if the remote file is accessible (quick HEAD request)
    if ! curl -s -f -I "$DOWNLOAD_URL" > /dev/null 2>&1; then
        echo -e "${YELLOW}Latest version not accessible. Continuing with existing version.${RESET}"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    # Compute hash of local binary
    if command -v sha256sum > /dev/null 2>&1; then
        LOCAL_HASH=$(sha256sum "$INSTALL_DIR/$ACTUAL_BINARY_NAME" | cut -d ' ' -f 1)
    else
        # Use shasum on macOS
        LOCAL_HASH=$(shasum -a 256 "$INSTALL_DIR/$ACTUAL_BINARY_NAME" | cut -d ' ' -f 1)
    fi
    
    # Download the latest binary to compare
    if ! curl -s -f -L "$DOWNLOAD_URL" -o "$TEMP_BINARY"; then
        echo -e "${YELLOW}Failed to download latest version. Continuing with existing version.${RESET}"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    # Compute hash of remote binary
    if command -v sha256sum > /dev/null 2>&1; then
        REMOTE_HASH=$(sha256sum "$TEMP_BINARY" | cut -d ' ' -f 1)
    else
        # Use shasum on macOS
        REMOTE_HASH=$(shasum -a 256 "$TEMP_BINARY" | cut -d ' ' -f 1)
    fi
    
    # If hashes match, no update needed
    if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
        echo -e "${GREEN}You already have the latest version of ${BINARY_NAME}.${RESET}"
        rm -rf "$TMP_DIR"
        return 0
    fi

    # Need to update - we already have the downloaded file
    echo -e "${YELLOW}A new version of ${BINARY_NAME} is available. Installing...${RESET}"
    
    # Make binary executable
    chmod +x "$TEMP_BINARY"
    
    # Install the new binary, using sudo if necessary
    if [ -w "$INSTALL_DIR" ]; then
        mv "$TEMP_BINARY" "${INSTALL_DIR}/${ACTUAL_BINARY_NAME}"
    else
        sudo mv "$TEMP_BINARY" "${INSTALL_DIR}/${ACTUAL_BINARY_NAME}" || {
            echo -e "${YELLOW}Update requires elevated permissions. Please run with sudo.${RESET}"
            rm -rf "$TMP_DIR"
            return 1
        }
    fi
    
    rm -rf "$TMP_DIR"
    echo -e "${GREEN}Update complete!${RESET}"
    return 0
}

# Check for updates synchronously
check_and_update

# Run the actual binary with all arguments
echo -e "${BLUE}Executing ${BINARY_NAME} command...${RESET}"
"$INSTALL_DIR/$ACTUAL_BINARY_NAME" "$@"
EOL

# Make wrapper script executable
chmod +x "${TMP_DIR}/${BINARY_NAME}"

# Install wrapper script
if [ -w "$INSTALL_DIR" ]; then
    mv "${TMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
else
    echo -e "${YELLOW}Elevated permissions required to install wrapper to ${INSTALL_DIR}${RESET}"
    sudo mv "${TMP_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
fi

# Cleanup
rm -rf "$TMP_DIR"

# Verify installation
if command -v "$BINARY_NAME" &>/dev/null; then
    echo -e "${GREEN}Successfully installed ${BINARY_NAME} to ${INSTALL_DIR}${RESET}"
    echo -e "${YELLOW}You can now run '${BINARY_NAME}' from your terminal.${RESET}"
    echo -e "${YELLOW}The command will automatically check for updates when run.${RESET}"
    
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
