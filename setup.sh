#!/bin/bash

set -e

REPO_URL=$(git remote get-url origin)

# MANIFEST CUSTOMIZATION

find app-of-apps -name "*.yaml" -type f | while read -r file; do
  # Does not work in Linux
  sed -i '' "s|\${REPO_URL}|$REPO_URL|g" "$file"
done

git add app-of-apps

git commit -m "Bootstrap: configure repository URL"
git push origin HEAD
echo "Changes commited"
