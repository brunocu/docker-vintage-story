FROM mcr.microsoft.com/dotnet/runtime:10.0-noble

# Install required tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    jq \
    ca-certificates \
    gosu \
    tar && \
    rm -rf /var/lib/apt/lists/*

# Additional .NET runtimes for older Vintage Story releases.
ENV DOTNET_ROOT=/usr/share/dotnet
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    chmod +x /tmp/dotnet-install.sh && \
    /tmp/dotnet-install.sh --runtime dotnet --channel 8.0 \
        --install-dir "$DOTNET_ROOT" --no-path && \
    /tmp/dotnet-install.sh --runtime dotnet --channel 7.0 \
        --install-dir "$DOTNET_ROOT" --no-path && \
    rm -f /tmp/dotnet-install.sh && \
    dotnet --list-runtimes

# Create vintagestory user (default for standalone mode).
#
# Ubuntu 24.04 ships a default "ubuntu" user already holding uid/gid 1000,
# so it has to be removed first
RUN if getent passwd 1000 >/dev/null; then \
        userdel -r "$(getent passwd 1000 | cut -d: -f1)" 2>/dev/null || true; \
    fi && \
    if getent group 1000 >/dev/null; then \
        groupdel "$(getent group 1000 | cut -d: -f1)" 2>/dev/null || true; \
    fi && \
    groupadd -g 1000 vintagestory && \
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
