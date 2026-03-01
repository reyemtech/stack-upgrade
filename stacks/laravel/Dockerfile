# ── Stage 1: Builder — compile PHP extensions ──────────────────────────
FROM php:8.4-cli-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    libzip-dev libxml2-dev libcurl4-openssl-dev \
    libonig-dev libicu-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install -j$(nproc) \
    pdo_sqlite \
    zip mbstring xml curl bcmath pcntl intl

# ── Stage 2: Final — lean runtime image ────────────────────────────────
FROM php:8.4-cli-bookworm

# Runtime libraries (no -dev packages)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libzip4 libxml2 libcurl4 \
    libonig5 libicu72 \
    git ssh-client unzip curl \
    gettext-base jq \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled PHP extensions from builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Node 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (for auto PR creation)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Non-root user (Claude Code refuses to run as root)
RUN useradd -m -s /bin/bash agent \
    && mkdir -p /workspace /output /skill \
    && chown -R agent:agent /workspace /output

# Copy skill files
COPY --chown=agent:agent templates/ /skill/templates/
COPY --chown=agent:agent scripts/ /skill/scripts/
COPY --chown=agent:agent kickoff-prompt.txt /skill/kickoff-prompt.txt
COPY --chown=agent:agent entrypoint.sh /skill/entrypoint.sh
RUN chmod +x /skill/entrypoint.sh /skill/scripts/*.sh

VOLUME /output
WORKDIR /workspace

USER agent

ENTRYPOINT ["/skill/entrypoint.sh"]
