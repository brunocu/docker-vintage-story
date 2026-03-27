#!/bin/bash
set -e

# Determine target user (reading from environment, not bash built-ins)
# Use printenv to read from process environment table, avoiding bash UID built-in
# The || handles the case where the env var doesn't exist (preventing set -e from exiting)
TARGET_UID=$(printenv UID 2>/dev/null || echo "1000")
TARGET_GID=$(printenv GID 2>/dev/null || echo "1000")

echo "=== Vintage Story Dedicated Server Entrypoint ==="
echo "Requested UID: $TARGET_UID, GID: $TARGET_GID"

# Adjust vintagestory user to match requested UID/GID
if [[ $TARGET_UID != 0 ]]; then
    CURRENT_UID=$(id -u vintagestory)
    if [[ $TARGET_UID != $CURRENT_UID ]]; then
        echo "Changing UID of vintagestory user from $CURRENT_UID to $TARGET_UID"
        usermod -u $TARGET_UID vintagestory
    fi
fi

if [[ $TARGET_GID != 0 ]]; then
    CURRENT_GID=$(id -g vintagestory)
    if [[ $TARGET_GID != $CURRENT_GID ]]; then
        echo "Changing GID of vintagestory group from $CURRENT_GID to $TARGET_GID"
        groupmod -o -g $TARGET_GID vintagestory
    fi
fi

# Default configuration
VS_VERSION=${VS_VERSION:-stable}
VS_PORT=${VS_PORT:-42420}

SERVER_DIR="/data/.vs-server"
VERSION_FILE="$SERVER_DIR/.version"
API_BASE_URL="https://api.vintagestory.at"

echo "Requested version: $VS_VERSION"

# Ensure data directory exists
mkdir -p /data

# Resolve version if "stable" or "unstable" specified
RESOLVED_VERSION="$VS_VERSION"
if [[ "$VS_VERSION" == "stable" ]] || [[ "$VS_VERSION" == "unstable" ]]; then
    echo "Resolving $VS_VERSION version from API..."
    # Use dedicated endpoint for stable or unstable
    API_URL="${API_BASE_URL}/${VS_VERSION}.json"
    API_DATA=$(curl -sL "$API_URL")

    # Find the version with "latest": 1 in the linuxserver platform
    RESOLVED_VERSION=$(echo "$API_DATA" | jq -r 'to_entries[] | select(.value.linuxserver.latest == 1) | .key')

    if [[ -z "$RESOLVED_VERSION" ]] || [[ "$RESOLVED_VERSION" == "null" ]]; then
        echo "ERROR: Failed to resolve $VS_VERSION version from API"
        exit 1
    fi
    echo "Resolved to version: $RESOLVED_VERSION"
else
    echo "Using specified version: $RESOLVED_VERSION"
fi

# Check if server needs to be downloaded
NEEDS_DOWNLOAD=false
if [[ ! -f "$VERSION_FILE" ]]; then
    echo "No cached server found"
    NEEDS_DOWNLOAD=true
elif [[ "$(cat $VERSION_FILE)" != "$RESOLVED_VERSION" ]]; then
    echo "Cached version $(cat $VERSION_FILE) differs from requested $RESOLVED_VERSION"
    NEEDS_DOWNLOAD=true
else
    echo "Using cached server version $RESOLVED_VERSION"
fi

# Download and install server if needed
if [[ "$NEEDS_DOWNLOAD" == "true" ]]; then
    echo "Downloading Vintage Story Server $RESOLVED_VERSION..."

    # Get download URL and MD5 from API for the specific version
    if [[ -z "$API_DATA" ]]; then
        # Fetch from the combined stable-unstable endpoint
        API_DATA=$(curl -sL "${API_BASE_URL}/stable-unstable.json")
    fi

    DOWNLOAD_URL=$(echo "$API_DATA" | jq -r --arg ver "$RESOLVED_VERSION" '.[$ver].linuxserver.urls.cdn // empty')
    EXPECTED_MD5=$(echo "$API_DATA" | jq -r --arg ver "$RESOLVED_VERSION" '.[$ver].linuxserver.md5 // empty')

    if [[ -z "$DOWNLOAD_URL" ]] || [[ "$DOWNLOAD_URL" == "null" ]]; then
        echo "ERROR: Failed to get download URL from API for version $RESOLVED_VERSION"
        echo "Available versions:"
        echo "$API_DATA" | jq -r 'keys[]' | head -10
        exit 1
    fi

    echo "Download URL: $DOWNLOAD_URL"

    # Download with retries
    DOWNLOAD_SUCCESS=false
    for attempt in {1..3}; do
        echo "Download attempt $attempt of 3..."
        if curl -L -o /tmp/vs-server.tar.gz "$DOWNLOAD_URL"; then
            DOWNLOAD_SUCCESS=true
            break
        fi
        echo "Download failed, retrying in 10 seconds..."
        sleep 10
    done

    if [[ "$DOWNLOAD_SUCCESS" != "true" ]]; then
        echo "ERROR: Failed to download server after 3 attempts"
        if [[ -f "$SERVER_DIR/VintageStoryServer" ]]; then
            echo "WARNING: Using cached version as fallback"
        else
            exit 1
        fi
    else
        # Verify MD5 checksum if available
        if [[ -n "$EXPECTED_MD5" ]] && [[ "$EXPECTED_MD5" != "null" ]]; then
            echo "Verifying MD5 checksum..."
            ACTUAL_MD5=$(md5sum /tmp/vs-server.tar.gz | awk '{print $1}')
            if [[ "$ACTUAL_MD5" != "$EXPECTED_MD5" ]]; then
                echo "ERROR: MD5 checksum mismatch!"
                echo "Expected: $EXPECTED_MD5"
                echo "Got: $ACTUAL_MD5"
                rm -f /tmp/vs-server.tar.gz
                exit 1
            fi
            echo "MD5 checksum verified"
        fi

        # Extract server
        echo "Extracting server files..."
        rm -rf "$SERVER_DIR"
        mkdir -p "$SERVER_DIR"
        tar -xzf /tmp/vs-server.tar.gz -C "$SERVER_DIR"
        rm -f /tmp/vs-server.tar.gz

        # Save version
        echo "$RESOLVED_VERSION" > "$VERSION_FILE"
        echo "Server version $RESOLVED_VERSION installed successfully"
    fi
fi

# Fix ownership of all files in /data
echo "Setting ownership to $TARGET_UID:$TARGET_GID..."
chown -R "$TARGET_UID:$TARGET_GID" /data

# Drop privileges and start server
echo "Starting Vintage Story Server as UID $TARGET_UID..."
exec gosu "$TARGET_UID:$TARGET_GID" "$SERVER_DIR/VintagestoryServer" \
    --dataPath /data \
    --port "$VS_PORT" \
    --ip 0.0.0.0
