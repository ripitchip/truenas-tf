#!/usr/bin/env bash
set -u

if [ -f ~/.ssh/id_rsa ]; then
    chmod 600 ~/.ssh/id_rsa
else
    echo "WARNING: ~/.ssh/id_rsa not found (mount failed?)"
fi

echo "=> OpenTofu init (local backend disabled)..."
tofu init -backend=false || echo "tofu init failed (did you 'cp secret.auto.tfvars.example secret.auto.tfvars'?)"

tofu version
