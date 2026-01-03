#!/bin/bash
set -euo pipefail

CONTEXTS=$(<"contexts.txt")

for ctx in $CONTEXTS; do
  minikube --profile $ctx delete
done

# Remove image
