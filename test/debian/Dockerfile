FROM debian:13

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      sudo

ENV LANG=C.UTF-8

# Debian images ship no regular user (unlike ubuntu:latest); create one with
# passwordless sudo
RUN useradd --create-home --shell /bin/bash debian && \
    echo "debian ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/debian && \
    chmod 0440 /etc/sudoers.d/debian

# Preserve proxy env vars across sudo so apt/curl honor http(s)_proxy
RUN echo 'Defaults env_keep += "http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY"' \
      > /etc/sudoers.d/00-proxy && \
    chmod 0440 /etc/sudoers.d/00-proxy

USER debian
WORKDIR /home/debian

RUN mkdir -p $HOME/.config $HOME/.local/share
