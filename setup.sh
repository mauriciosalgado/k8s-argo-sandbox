#!/bin/bash

set -euo pipefail

REPO_URL=$(git remote get-url origin)

# DEPENDENCY CHECKS

for bin in git minikube kubectl ssh-keyscan; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Error: required command '$bin' is not installed or not in PATH"
    exit 1
  fi
done

# CHECK IF ALREADY RUN

if ! grep -R "\${REPO_URL}" app-of-apps >/dev/null; then
  echo "Repository already personalized"
  exit 0
fi

# MANIFEST CUSTOMIZATION

echo "Personalizing repository with REPO_URL=$REPO_URL"

find app-of-apps -name "*.yaml" -type f | while read -r file; do
  tmp=$(mktemp)
  sed "s|\${REPO_URL}|$REPO_URL|g" "$file" >"$tmp"
  mv "$tmp" "$file"
done

git add app-of-apps

git commit -m "Bootstrap: configure repository URL"
git push origin HEAD
echo "Changes commited"
