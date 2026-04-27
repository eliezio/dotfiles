FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      sudo

ENV LANG=C.UTF-8

# Allow existing ubuntu user to use sudo without password
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu && \
    chmod 0440 /etc/sudoers.d/ubuntu

# Preserve proxy env vars across sudo so apt/curl honor http(s)_proxy
RUN echo 'Defaults env_keep += "http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY"' \
      > /etc/sudoers.d/00-proxy && \
    chmod 0440 /etc/sudoers.d/00-proxy

USER ubuntu
WORKDIR /home/ubuntu
