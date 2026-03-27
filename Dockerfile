FROM mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim

# Install required tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    jq \
    ca-certificates \
    gosu \
    tar && \
    rm -rf /var/lib/apt/lists/*

# Create vintagestory user (default for standalone mode)
RUN groupadd -g 1000 vintagestory && \
    useradd -u 1000 -g vintagestory -m -s /bin/bash vintagestory

# Create data directory
RUN mkdir -p /data && chmod 755 /data

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose game server port (TCP for reliable data, UDP for position updates)
EXPOSE 42420/tcp
EXPOSE 42420/udp

# Run as root by default (entrypoint will drop privileges)
# NO USER directive - entrypoint handles privilege dropping
ENTRYPOINT ["/entrypoint.sh"]
