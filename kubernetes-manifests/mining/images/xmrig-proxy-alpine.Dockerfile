# Alpine-based XMRig Proxy
# Minimal relay — static binary on Alpine
FROM alpine:3.21

ARG XMRIG_VERSION=6.25.0

RUN apk add --no-cache libgcc libstdc++ ca-certificates && \
    wget -qO /tmp/xmrig.tar.gz "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/xmrig-6-25-0/xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz" && \
    tar -xzf /tmp/xmrig.tar.gz -C /tmp && \
    mv /tmp/xmrig /usr/local/bin/xmrig-proxy && \
    chmod +x /usr/local/bin/xmrig-proxy && \
    rm -rf /tmp/xmrig.tar.gz

ENTRYPOINT ["xmrig-proxy"]
