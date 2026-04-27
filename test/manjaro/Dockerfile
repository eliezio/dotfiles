FROM manjarolinux/base:latest

RUN useradd -m -G wheel -s /bin/zsh manjaro \
      && echo 'manjaro ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
      && echo 'Defaults env_keep += "http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY"' \
         > /etc/sudoers.d/00-proxy \
      && chmod 0440 /etc/sudoers.d/00-proxy

RUN sudo pacman-mirrors -f

USER manjaro
WORKDIR /home/manjaro
