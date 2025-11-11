FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && \
    apt-get install -y \
    git-lfs python3 python3-doc \
    python3-tk python3-venv python3.12-venv \
    python3.12-doc binfmt-support \
    python3-pip && \
    rm -rf /var/lib/apt/lists/*