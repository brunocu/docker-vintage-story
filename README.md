# Vintage Story Containerized Server

A custom container image for running a Vintage Story dedicated server.

## Features

- **Runtime CDN downloads**: Server binary downloaded on first start from official CDN
- **Automatic version resolution**: Specify "stable" or "unstable" to always get latest
- **Environment variable configuration**: `VS_VERSION` and `VS_PORT` are configurable via env vars.
- **Multi-version support**: Bundles multiple .NET runtimes.

## Supported Versions

| Vintage Story version | .NET runtime |
|---|---|
| 1.18.8 – 1.20.x | 7 |
| 1.21.x | 8 |
| 1.22.0 and later | 10 |

Versions before 1.18.8 used Mono and are not supported by this image.

## Quick Start

### Minimum Working Example

```bash
docker run -d \
  -p 42420:42420/tcp \
  -p 42420:42420/udp \
  ghcr.io/brunocu/docker-vintage-story:latest
```

This will:
- Download the latest stable Vintage Story server
- Create a default world
- Start the server on port 42420

### With Persistent Storage

```bash
mkdir -p ~/vintagestory-data

docker run -d \
  -p 42420:42420/tcp \
  -p 42420:42420/udp \
  -v ~/vintagestory-data:/data \  # Mount host directory for persistent data
  ghcr.io/brunocu/docker-vintage-story:latest
```

### With Custom Configuration

```bash
# Start server on custom version and port
docker run -d \
  -p 42421:42421/tcp \
  -p 42421:42421/udp \
  -v ~/vintagestory-data:/data \
  -e VS_VERSION="1.21.6" \
  -e VS_PORT="42421" \
  ghcr.io/brunocu/docker-vintage-story:latest
```

**Note:** Server name, passwords, max clients, and other settings must be configured via commands or editing `/data/serverconfig.json` after initial generation. See [Setting up a Multiplayer Server](https://wiki.vintagestory.at/index.php?title=Setting_up_a_Multiplayer_Server#Basic_Configuration) for details.
## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `VS_VERSION` | `stable` | Server version. Use `stable`, `unstable`, or a specific version like `1.21.0`. |
| `VS_PORT` | `42420` | Server port. |


## How It Works

### Container Startup Flow

1. **Determines target user**: Uses `UID`/`GID` env vars if provided, otherwise defaults to 1000:1000
2. **Version resolution**: If `VS_VERSION` is "stable" or "unstable", queries API for latest version
3. **Download check**: Compares requested version against cached version in `/data/.vs-server/.version`
4. **Download if needed**:
   - Fetches download URL and MD5 from API manifest
   - Downloads server tarball from CDN
   - Verifies MD5 checksum
   - Extracts to `/data/.vs-server/`
   - Saves version to tracking file
5. **Drop privileges**: Executes server as non-root user
6. **Start server**: Runs `VintagestoryServer --dataPath /data --port $VS_PORT --ip 0.0.0.0`

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
  ghcr.io/brunocu/docker-vintage-story:latest
```

## Troubleshooting

### Download Failures

**Symptom**: Container logs show "Failed to download server after 3 attempts"

**Solutions**:
- Check container internet connectivity: `docker exec vintagestory curl -I https://api.vintagestory.at`
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
- Stop conflicting service or change port mapping: e.g. `-p 42421:42420`

### UDP Not Working (Position Updates Laggy)

**Symptom**: Server logs show "UDP: Server did not receive any UDP packets from Client, telling the client to send positions over TCP"

**Cause**: UDP port not exposed in Docker

**Solution**: Ensure both TCP and UDP ports are exposed:
```bash
docker run -d \
  -p 42420:42420/tcp \
  -p 42420:42420/udp \
  -v ~/vintagestory-data:/data \
  ghcr.io/brunocu/docker-vintage-story:latest
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

This container image is provided as-is. Vintage Story is a trademark of Anego Studios SIA.

## Support

For issues with:
- **Container image**: Open an issue on this repository
- **Vintage Story game**: Visit https://www.vintagestory.at/
