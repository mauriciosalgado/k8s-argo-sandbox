#!/bin/bash

CONTEXTS=$(cat "contexts.txt")

for ctx in $CONTEXTS; do
  echo "ArgoCD UI password for $ctx:"
  kubectl get secret --context $ctx -n argocd argocd-initial-admin-secret -o yaml | grep -i password | awk '{print $2}' | base64 -d
  echo ""
  echo ""
done
