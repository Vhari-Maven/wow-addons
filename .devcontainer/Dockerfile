FROM docker.io/oven/bun:1-debian

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

USER root

# Base dev tools + project-specific: python toolchain, sqlite CLI, luacheck (apt),
# build deps for the stylua binary fetch.
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  wget \
  curl \
  ca-certificates \
  python3 \
  python3-pip \
  python3-venv \
  sqlite3 \
  lua-check \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG USERNAME=bun

# Persist bash history.
RUN mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME:$USERNAME /commandhistory

ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/$USERNAME/.claude && \
  chown -R $USERNAME:$USERNAME /workspace /home/$USERNAME/.claude

WORKDIR /workspace

# git-delta for nicer diffs
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# stylua — Lua formatter (prebuilt binary from GitHub releases)
ARG STYLUA_VERSION=2.0.2
RUN ARCH=$(dpkg --print-architecture) && \
  case "$ARCH" in \
    amd64) STYLUA_ARCH=linux-x86_64 ;; \
    arm64) STYLUA_ARCH=linux-aarch64 ;; \
    *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
  esac && \
  wget -q "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-${STYLUA_ARCH}.zip" -O /tmp/stylua.zip && \
  unzip -q /tmp/stylua.zip -d /usr/local/bin/ && \
  chmod +x /usr/local/bin/stylua && \
  rm /tmp/stylua.zip

USER $USERNAME

ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

# zsh + powerlevel10k
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -a "[ -r /run/secrets/github-token ] && export GH_TOKEN=\$(cat /run/secrets/github-token)" \
  -x

# Install Claude Code via bun (no Node in this image).
# Same trick as the reference: bun's hardcoded global bin path is unwritable by
# the non-root user, so we redirect BUN_INSTALL and symlink the shim ourselves.
ENV BUN_INSTALL=/home/$USERNAME/.bun
RUN mkdir -p $BUN_INSTALL/bin && \
  bun install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} && \
  ln -sf $BUN_INSTALL/install/global/node_modules/@anthropic-ai/claude-code-linux-x64/claude $BUN_INSTALL/bin/claude
ENV PATH=$BUN_INSTALL/bin:/home/$USERNAME/.local/bin:$PATH

# ruff — Python lint + formatter. Installed per-user via pip so it lands in
# ~/.local/bin (added to PATH above). PEP 668 on Debian Bookworm blocks system
# pip installs without --break-system-packages, but --user is exempt.
RUN pip install --user --no-cache-dir --break-system-packages ruff==0.8.4

# Firewall script (init-firewall.sh) — runs at postStart
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "$USERNAME ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/${USERNAME}-firewall && \
  chmod 0440 /etc/sudoers.d/${USERNAME}-firewall
USER $USERNAME
