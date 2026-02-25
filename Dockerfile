FROM php:8.4-cli-bookworm

# System deps (libicu-dev for ext-intl)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ssh-client unzip curl sqlite3 libsqlite3-dev \
    libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    libzip-dev libxml2-dev libcurl4-openssl-dev \
    libpq-dev libonig-dev libicu-dev gettext-base sudo \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions (including intl for Filament)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    pdo_mysql pdo_pgsql pdo_sqlite \
    gd zip mbstring xml curl bcmath pcntl intl

# Redis extension
RUN pecl install redis && docker-php-ext-enable redis

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Node 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
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
