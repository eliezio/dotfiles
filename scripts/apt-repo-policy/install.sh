#!/bin/bash
# Install apt-repo-policy onto this machine (needs root). Idempotent.
# Tests are not run here: they need populated apt lists, absent on a fresh machine.
set -eu
cd "$(dirname "$0")"
install -m 755 sbin/apt-repo-audit sbin/apt-repo-allow /usr/local/sbin/
install -m 644 etc/apt/preferences.d/*.pref /etc/apt/preferences.d/
install -m 644 etc/apt/apt.conf.d/99apt-repo-audit /etc/apt/apt.conf.d/
# Warn-only: an existing violation must not fail `chezmoi apply`.
/usr/local/sbin/apt-repo-audit || true
