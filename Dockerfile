FROM php:8.4-cli-bookworm

# System deps (matching reyemtech/sail extensions)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ssh-client unzip curl sqlite3 libsqlite3-dev \
    libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev \
    libzip-dev libxml2-dev libcurl4-openssl-dev \
    libpq-dev libonig-dev libicu-dev libsodium-dev \
    gettext-base jq \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions (matching reyemtech/sail)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) \
    pdo_mysql pdo_pgsql pdo_sqlite pgsql \
    gd zip mbstring xml curl bcmath pcntl intl \
    exif opcache sodium

# Redis extension
RUN pecl install redis && docker-php-ext-enable redis

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
