#!/bin/bash

set -e

CONTEXTS=$(<"contexts.txt")
REPO_URL=$(git remote get-url origin)
GIT_HOST=$(echo "$REPO_URL" | sed -E 's/.*@([^:]+):.*/\1/')
BOOTSTRAP_TEMPLATE="app-of-apps/argocd/bootstrap/root-app-template.yaml"
SSH_KEY="$HOME/.ssh/argocd-ssh"
SSH_KNOWN_HOSTS=$(ssh-keyscan "$GIT_HOST" 2>/dev/null)

# CHECKS

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH key \"argocd-ssh\" not found: $SSH_KEY"
  exit 1
fi

# BOOTSTRAPPING

for ctx in $CONTEXTS; do
  minikube --profile "$ctx" start
done

for ctx in $CONTEXTS; do
  kubectl config use-context "$ctx"

  echo "Creating namespace"
  kubectl --context "$ctx" create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  echo "Installing ArgoCD"
  kubectl --context "$ctx" apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  kubectl --context "$ctx" -n argocd create configmap argocd-ssh-known-hosts-cm \
    --from-literal=ssh_known_hosts="$SSH_KNOWN_HOSTS" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl --context "$ctx" -n argocd rollout restart deployment argocd-repo-server

  echo "Creating Repo Credentials Secret"
  kubectl --context "$ctx" create secret generic private-repo \
    -n argocd \
    --from-literal=type=git \
    --from-literal=url="$REPO_URL" \
    --from-file=sshPrivateKey="$SSH_KEY" \
    --dry-run=client -o yaml |
    kubectl label --local -f - \
      argocd.argoproj.io/secret-type=repo-creds \
      -o yaml |
    kubectl apply -f -

  echo "Waiting for Argo CD to be ready"
  kubectl --context "$ctx" wait deployment argocd-server \
    -n argocd \
    --for=condition=Available=True \
    --timeout=300s

  echo "Bootstrapping ArgoCD Root Application in $ctx"
  CLUSTER_ENV="$ctx"
  envsubst <$BOOTSTRAP_TEMPLATE | kubectl apply -f -
done
