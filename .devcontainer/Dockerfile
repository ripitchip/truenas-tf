FROM mcr.microsoft.com/devcontainers/base:debian-12

# Tools required by scripts/deploy_vm.sh (TrueNAS API, Cloud-Init seed)
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    git \
    jq \
    gnupg \
    openssh-client \
    genisoimage \
    ca-certificates \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# OpenTofu CLI via the official APT repository (drop-in Terraform replacement,
# same HCL syntax): https://opentofu.org/docs/intro/install/deb/
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://get.opentofu.org/opentofu.gpg -o /etc/apt/keyrings/opentofu.gpg \
    && curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey -o /tmp/opentofu-repo.asc \
    && gpg --no-tty --batch --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg /tmp/opentofu-repo.asc \
    && rm -f /tmp/opentofu-repo.asc \
    && chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" > /etc/apt/sources.list.d/opentofu.list \
    && echo "deb-src [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" >> /etc/apt/sources.list.d/opentofu.list \
    && chmod a+r /etc/apt/sources.list.d/opentofu.list \
    && apt-get update \
    && apt-get install -y tofu \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /home/vscode/.ssh && chown vscode:vscode /home/vscode/.ssh && chmod 700 /home/vscode/.ssh
