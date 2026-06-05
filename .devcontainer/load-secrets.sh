#!/usr/bin/env bash
#
# load-secrets.sh — create podman secrets from the GPG-encrypted store in ~/.secrets-enc.
#
# Runs on the HOST via devcontainer.json `initializeCommand`, before the container
# is created. Each entry decrypts <name>.gpg into a named podman secret, which is
# then mounted into the container at /run/secrets/<filename> by the matching
# `--secret=...,type=mount,...` lines in devcontainer.json `runArgs`.
#
# Adding/rotating a key:
#   gpg -r jimmybdavis@gmail.com -o ~/.secrets-enc/<name>.gpg --encrypt <plaintext>
#   (then rm the plaintext). View one with:  gpg -d ~/.secrets-enc/<name>.gpg
#
set -uo pipefail

ENC_DIR="${HOME}/.secrets-enc"

# podman-secret-name : source filename (decrypted from <filename>.gpg)
KEYS=(
  "github_token:github-token"
  "anthropic_key:anthropic-api-key"
  "openrouter_key:openrouter-api-key"
)

for entry in "${KEYS[@]}"; do
  name="${entry%%:*}"
  file="${entry##*:}"
  enc="${ENC_DIR}/${file}.gpg"
  if [[ -r "$enc" ]]; then
    if gpg --batch -q -d "$enc" 2>/dev/null | podman secret create --replace "$name" - >/dev/null; then
      echo "secret: $name <- $enc (decrypted)"
    else
      echo "warn: failed to load secret $name from $enc" >&2
    fi
  else
    echo "warn: $enc not found — skipping $name" >&2
  fi
done
