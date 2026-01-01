#!/bin/bash

CONTEXTS=$(cat "contexts.txt")
REPO_URL="git@atc-github.azure.cloud.bmw:Extended-Enterprise-Catena-X/dsf-argo-sandbox.git"
BOOTSTRAP_TEMPLATE="app-of-apps/argocd/bootstrap/root-app-template.yaml"
SSH_KEY="$HOME/.ssh/argocd-ssh"
SSH_KNOWN_HOSTS=$(ssh-keyscan atc-github.azure.cloud.bmw)

for ctx in $CONTEXTS; do
  minikube --profile $ctx start
done

for ctx in $CONTEXTS; do
  kubectl config use-context $ctx

  echo "Creating namespace"
  kubectl create namespace argocd

  echo "Installing ArgoCD"
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  kubectl -n argocd create configmap argocd-ssh-known-hosts-cm \
    --from-literal=ssh_known_hosts="$SSH_KNOWN_HOSTS" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl -n argocd rollout restart deployment argocd-repo-server

  echo "Creating Repo Credentials Secret"
  kubectl create secret generic private-repo \
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
  kubectl wait deployment argocd-server \
    -n argocd \
    --for=condition=Available=True \
    --timeout=300s

  echo "Bootstrapping Application"
  sed "s|<cluster-env>|$ctx|g" "$BOOTSTRAP_TEMPLATE" | kubectl apply -f -
done
