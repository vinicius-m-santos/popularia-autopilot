FROM node:22.21.1-bookworm-slim AS cezar-build

ARG CEZAR_REPO=https://github.com/vinicius-m-santos/cezar.git
ARG CEZAR_COMMIT=6d280bee4fd607554464a24be1276bf147960665

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/cezar-source
RUN git clone --depth 1 "${CEZAR_REPO}" . \
    && git fetch --depth 1 origin "${CEZAR_COMMIT}" \
    && git checkout --detach "${CEZAR_COMMIT}" \
    && npm install --ignore-scripts --no-audit --no-fund \
    && npm run build \
    && npm pack -w @open-mercato/cezar --pack-destination /tmp

FROM node:22.21.1-bookworm-slim

ARG OPENCODE_VERSION=1.19.5
ARG CODEX_VERSION=0.166.0
ARG CLAUDE_CODE_VERSION=2.1.318

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/data/home \
    CEZ_HOME=/data/cezar \
    CEZ_BROWSE_ROOT=/data/workspaces \
    CEZ_PROJECTS_DIR=/data/workspaces \
    XDG_CONFIG_HOME=/data/home/.config \
    XDG_DATA_HOME=/data/home/.local/share \
    CEZ_REMOTE=1 \
    CEZ_REMOTE_AGENT_ACCOUNTS=1 \
    CEZ_TERMINAL=0 \
    CEZ_AUTOMATIONS=0 \
    CEZ_AUTONOMOUS_DEFAULT=0 \
    CEZ_WORKTREE_DEFAULT=1 \
    CEZ_REVIEW_GATE=1 \
    CEZ_TELEMETRY=0 \
    CEZ_NO_BANNER=1 \
    PORT=8080

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apache2-utils \
        ca-certificates \
        composer \
        curl \
        git \
        gh \
        gosu \
        nginx \
        openssh-client \
        php-cli \
        php-curl \
        php-intl \
        php-mbstring \
        php-sqlite3 \
        php-xml \
        php-zip \
        tini \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Cezar currently drives the OpenCode 1.x server protocol. Keep every CLI pinned
# so a rebuild cannot silently change the orchestration or authentication surface.
COPY --from=cezar-build /tmp/open-mercato-cezar-0.19.0.tgz /tmp/
RUN npm install --global \
      /tmp/open-mercato-cezar-0.19.0.tgz \
      "opencode-ai@${OPENCODE_VERSION}" \
      "@openai/codex@${CODEX_VERSION}" \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force \
    && cezar-run --help >/dev/null \
    && opencode --version \
    && codex --version \
    && claude --version

RUN useradd --no-create-home --home-dir /data/home --shell /bin/bash --uid 10001 cezar \
    && mkdir -p /opt/popularia-bootstrap /data /run/cezar \
    && chown -R cezar:cezar /opt/popularia-bootstrap /data /run/cezar

COPY --chown=cezar:cezar .ai /opt/popularia-bootstrap/.ai
COPY --chown=cezar:cezar config/bootstrap-README.md /opt/popularia-bootstrap/README.md
COPY --chown=cezar:cezar config/workspace-config.json /opt/popularia-bootstrap-config.json
COPY docker/nginx.conf.template /etc/nginx/nginx.conf.template
COPY docker/cezar-entrypoint.sh /usr/local/bin/cezar-entrypoint

RUN chmod 0755 /usr/local/bin/cezar-entrypoint

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD curl --fail --silent --show-error "http://127.0.0.1:${PORT}/healthz" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/cezar-entrypoint"]
