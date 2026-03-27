# Vintage Story Dedicated Server Container

A custom container image for running a Vintage Story dedicated server.

## Features

- **Runtime CDN downloads**: Server binary downloaded on first start from official CDN
- **Automatic version resolution**: Specify "stable" or "unstable" to always get latest
- **Environment variable configuration**: All server settings configurable via env vars
- **Persistent storage**: World data and configs stored in `/data` volume

## Quick Start

### Minimum Working Example

```bash
docker run -d -p 42420:42420/tcp -p 42420:42420/udp ghcr.io/YOUR_USERNAME/vintage-story:latest
```

This will:
- Download the latest stable Vintage Story server
- Create a default world
- Start the server on port 42420
- Store all data in the container's `/data` volume

### With Persistent Storage

```bash
mkdir -p ~/vintagestory-data

docker run -d \
  -p 42420:42420/tcp \
  -p 42420:42420/udp \
  -v ~/vintagestory-data:/data \
  ghcr.io/YOUR_USERNAME/vintage-story:latest
```

### With Custom Configuration

```bash
# Start server on custom port
docker run -d \
  -p 42421:42421/tcp \
  -p 42421:42421/udp \
  -v ~/vintagestory-data:/data \
  -e VS_VERSION="1.21.6" \
  -e VS_PORT="42421" \
  ghcr.io/YOUR_USERNAME/vintage-story:latest

# Wait for first run to complete (generates default config)
docker logs -f <container_name>

# Edit the generated config file
vim ~/vintagestory-data/serverconfig.json

# Restart to apply changes
docker restart <container_name>
```

**Note:** Server name, passwords, max clients, and other settings must be configured by editing `/data/serverconfig.json` after initial generation.

## Environment Variables

### Version Management

| Variable | Default | Description |
|----------|---------|-------------|
| `VS_VERSION` | `stable` | Server version. Use "stable", "unstable", or specific version like "1.21.0" |

### Server Configuration (Command Line)

| Variable | Default | Description |
|----------|---------|-------------|
| `VS_PORT` | `42420` | Server port (TCP) |

**Note:** Most server configuration (server name, max clients, passwords, world settings, etc.) should be done via commands, or editing `/data/serverconfig.json` after the server generates it on first run: [Basic configuration guide](https://wiki.vintagestory.at/index.php?title=Setting_up_a_Multiplayer_Server#Basic_Configuration)

## Building the Image

### Prerequisites

- Docker or Podman installed
- GitHub account (for pushing to ghcr.io)
- GitHub Personal Access Token with `write:packages` scope

### Build

```bash
cd containers/vintage-story
docker build -t vintage-story:local .
```

### Test Locally

```bash
# Create test data directory
mkdir -p test-data

# Run container with local image
docker run -d --name vs-test \
  -p 42420:42420/tcp \
  -p 42420:42420/udp \
  -v $(pwd)/test-data:/data \
  vintage-story:local

# Check logs (watch for version resolution and download)
docker logs -f vs-test

# Verify server is running
docker exec vs-test ps aux

# Stop and clean up
docker stop vs-test
docker rm vs-test
rm -rf test-data
```

### Push to GitHub Container Registry

```bash
# Tag for registry
docker tag vintage-story:local ghcr.io/YOUR_USERNAME/vintage-story:latest

# Authenticate
echo "YOUR_GITHUB_TOKEN" | docker login ghcr.io -u YOUR_USERNAME --password-stdin

# Push image
docker push ghcr.io/YOUR_USERNAME/vintage-story:latest
```

## How It Works

### Container Startup Flow

1. **Runs as root** (PID 1) to perform privileged setup
2. **Determines target user**: Uses `UID`/`GID` env vars if provided, otherwise defaults to 1000:1000
3. **Version resolution**: If `VS_VERSION` is "stable" or "unstable", queries dedicated API endpoint for latest version
4. **Download check**: Compares requested version against cached version in `/data/.vs-server/.version`
5. **Download if needed**:
   - Fetches download URL and MD5 from API manifest
   - Downloads server tarball from CDN (3 retries with 10s delay)
   - Verifies MD5 checksum
   - Extracts to `/data/.vs-server/`
   - Saves version to tracking file
6. **Fix ownership**: Runs `chown -R $TARGET_UID:$TARGET_GID /data` to ensure proper permissions
7. **Drop privileges**: Uses `gosu` to execute server as non-root user
8. **Start server**: Runs `VintagestoryServer --dataPath /data --port $VS_PORT --ip 0.0.0.0`
9. **First run**: Server generates default `/data/serverconfig.json` with all required fields, roles, and settings

### Directory Structure

```
/data/
├── .vs-server/              # Server binary (auto-downloaded)
│   ├── VintagestoryServer   # Main executable
│   ├── VintagestoryServer.dll
│   ├── assets/              # Game assets
│   ├── Lib/                 # Libraries
│   └── .version             # Version tracking file
├── serverconfig.json        # Generated from env vars
├── Worlds/                  # World saves
├── Logs/                    # Server logs
├── Mods/                    # Server mods (optional)
└── .cache/                  # Vintage Story cache
```

## Version Upgrades

To upgrade the server:

1. Change `VS_VERSION` environment variable
2. Restart the container

The entrypoint will:
- Detect version mismatch
- Download new server binary
- Preserve world data and configs
- Start with new version

```bash
# Stop container
docker stop vintagestory

# Start with new version
docker run -d --name vintagestory \
  -p 42420:42420/tcp \
  -p 42420:42420/udp \
  -v ~/vintagestory-data:/data \
  -e VS_VERSION="1.23.0" \
  ghcr.io/YOUR_USERNAME/vintage-story:latest
```

## Troubleshooting

### Download Failures

**Symptom**: Container logs show "Failed to download server after 3 attempts"

**Solutions**:
- Check internet connectivity: `docker exec vintagestory curl -I https://api.vintagestory.at`
- Verify API is accessible: `curl https://api.vintagestory.at/stable-unstable.json`
- Manually download and extract to `/data/.vs-server/` if CDN is unreachable

### MD5 Checksum Mismatch

**Symptom**: Container exits with "MD5 checksum mismatch!"

**Cause**: Downloaded file is corrupted or CDN provided wrong file

**Solutions**:
- Restart container to retry download
- If persistent, manually download from Vintage Story website and extract to `/data/.vs-server/`

### Port Already in Use

**Symptom**: Container starts but server fails to bind to port

**Solutions**:
- Check if port is in use: `netstat -tuln | grep 42420`
- Change port: `-e VS_PORT="42421"`
- Stop conflicting service or change port mapping: `-p 42421:42420`

### UDP Not Working (Position Updates Laggy)

**Symptom**: Server logs show "UDP: Server did not receive any UDP packets from Client, telling the client to send positions over TCP"

**Cause**: UDP port not exposed in Docker

**Solution**: Ensure both TCP and UDP ports are exposed:
```bash
docker run -d \
  -p 42420:42420/tcp \
  -p 42420:42420/udp \
  -v ~/vintagestory-data:/data \
  ghcr.io/YOUR_USERNAME/vintage-story:latest
```

### Disk Space

**Symptom**: Container fails to download or world saves fail

**Solutions**:
- Check disk space: `docker exec vintagestory df -h /data`
- Clean up old worlds or backups
- Increase volume size if using thin provisioning

## Acknowledgments

This container image's architecture and patterns were inspired by [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server).

## License

This container image is provided as-is. Vintage Story is a trademark of Aenigma Mundi Interactive GmbH.

## Support

For issues with:
- **Container image**: Open an issue on this repository
- **Vintage Story game**: Visit https://www.vintagestory.at/
