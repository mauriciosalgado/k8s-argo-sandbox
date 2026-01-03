# K8s ArgoCD Sandbox

This repository is a **template repository**, that allows for quick setup of a private repo that is meant to be used by ArgoCD as a **source of truth** for applications. It comes packaged with scripts that quickly bootstraps local k8s clusters and deploys ArgoCD in them, pointing to the new repository generated through this.

> [!IMPORTANT]
> cluster = context = environment

## Table Of Contents

<!-- toc -->

- [Usage](#usage)
- [Requirements](#requirements)
  * [Packages](#packages)
  * [SSH Key](#ssh-key)
- [Quick Start](#quick-start)
- [Run](#run)
  * [Contexts](#contexts)
  * [Diagram](#diagram)
- [Access ArgoCD UI](#access-argocd-ui)
  * [Initial Admin Password](#initial-admin-password)
  * [Port Forwarding Service](#port-forwarding-service)
- [Adding Apps](#adding-apps)
  * [YAML Based Apps](#yaml-based-apps)
  * [Helm Based Apps](#helm-based-apps)
    + [Remote Charts](#remote-charts)
  * [ArgoCD App Templating](#argocd-app-templating)
- [Tips](#tips)
  * [Alias](#alias)
  * [Check with k9s](#check-with-k9s)
- [Remove](#remove)
- [References](#references)

<!-- tocstop -->

## Usage

This repository is intended to be used as a **template repository**.

1. Click **Use this template**
2. Create a new private repository
3. Clone your new repository
4. Run `./setup.sh`

The setup script will inject the repoURL in the manifests and push the changes to the repo

## Requirements

### Packages

- [minikube](https://formulae.brew.sh/formula/minikube)
- [kubectl-cli](https://formulae.brew.sh/formula/kubernetes-cli)

### SSH Key

In order to give ArgoCD access to this repo, you need to:

- configure SSH access to this repo
- create the private key, with the name ***argocd-ssh***, in `~/.ssh`.

> [!NOTE]
> You can duplicate your existing ssh private key and change its name:
> `cp ~/.ssh/<your-private-ssh-key> ~/.ssh/argocd-ssh`

## Quick Start

```sh
# Customize Manifests
./setup.sh

# Deploy sandbox
./run.sh

# Get ArgoCD password
./pwd.sh
# Get the last one

# Port forward ArgoCD UI
kubectl port-forward --context cluster-prod svc/argocd-server -n argocd 8080:443
```

## Run

To deploy the sandbox, make sure all the requirements are met and run `run.sh`

### Contexts

The ***contexts.txt***  file is used to define the contexts/clusters to be created by `run.sh`

### Diagram

```mermaid
flowchart TD
    A[Read contexts.txt<br/> to $CONTEXTS]

    subgraph L [For $ctx in $CONTEXTS]
        S[Start Minikube cluster]
        S --> C[Install Argo CD]
        C --> D[Configure repo credentials<br/>via secret]
        D --> E[Apply root-app]
        E -.->|next context| S
    end

    A --> L
```

## Access ArgoCD UI

### Initial Admin Password

To get the initial admin password you can run `pwd.sh`

```sh
❯ ./pwd.sh
ArgoCD UI password for cluster-dev:
fw0kosWYIU0HiyX0

ArgoCD UI password for cluster-prod:
p9SYdMIvdIPktLCJ
```

### Port Forwarding Service

Then you can port-forward ArgoCD server service, of one or both clusters, to access UI:

```sh
kubectl port-forward --context cluster-dev svc/argocd-server -n argocd 8080:443
kubectl port-forward --context cluster-prod svc/argocd-server -n argocd 8081:443
```

## Adding Apps

### YAML Based Apps

For YAML Based Apps the following approach should be used:

```sh
nginx
├── base
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── service.yaml
└── overlays
    ├── cluster-dev
    │   ├── configMap.yaml
    │   └── kustomization.yaml
    └── cluster-prod
        ├── configMap.yaml
        └── kustomization.yaml
```

- a ***base***  directory, where we define the environment agnostic kubernetes resources
- a ***overlays*** directory, where we define environment specific kubernetes resources
- a ***kustomization.yaml*** file, both in base and overlays, that tells Kustomize how to build/manipulate Kubernetes resources

The pattern is to have a kustomization.yaml file in base directory and another in the overlays that references the base kustomization file and the overlay resources that are cluster specific.

> [!NOTE]
> Ultimately, when ArgoCD finds a kustomization file, it runs `kustomize build`, which generates the manifests.

Then, add an ArgoCD Application under `clusters/<cluster>`, as such:

```sh
cluster-prod
├── kustomization.yaml
└── nginx.yaml
```

Pointing the path to the right overlay, as such:

```yaml
source:
  repoURL: ${REPO_URL}
  targetRevision: main
  path: app-of-apps/apps/nginx/overlays/cluster-prod
```

And finally, add the app to ***kustomization.yaml*** under the environment for which we are configuring the app, so that ArgoCD can discover it:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namePrefix: prod-
resources:
  - nginx.yaml
```

### Helm Based Apps

#### Remote Charts

For remote helm based Apps the following approach should be used:

```sh
nginx-helm
└── values
    ├── cluster-dev.yaml
    └── cluster-prod.yaml

```

Then, in the ArgoCD Application, we need to use multiple sources, one for the helm chart, and one for the values file, that resides in our repo:

```yaml
sources:
  - repoURL: https://charts.bitnami.com/bitnami
    chart: nginx
    targetRevision: 22.3.8
    helm:
      valueFiles:
        - $path/app-of-apps/apps/nginx-helm/values/cluster-prod.yaml
  - repoURL: ${REPO_URL}
    targetRevision: main
    ref: path
```

> [!NOTE]
> Without multiple sources, it can't load our custom valuesFile because it will look for it in the chart repo

And finally add the ApplicationSet to ***kustomization.yaml*** under the environment in which we are deploying the app, so that ArgoCD can discover it:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namePrefix: prod-
resources:
  - nginx.yaml
  - nginx-helm.yaml <-
```

### ArgoCD App Templating

As an example for an application that needs to be deployed multiple times with different names/values, an  ApplicationSet named `edc.yaml`  was created, for each environment.

> [!NOTE]
> This simulates different ***use-cases*** being deployed using the same codebase

Let's take the generators section of the ApplicationSet, being deployed in "cluster-prod" as example:

```yaml
generators:
  - git:
      repoURL: ${REPO_URL}
      revision: main
      files:
        - path: app-of-apps/apps/edc/cluster-dev/*.yaml
```

And then you can use the same logic as for the single helm application, in the sources section of the template:

```yaml
template:
  sources:
    - repoURL: https://charts.bitnami.com/bitnami
      chart: nginx
      targetRevision: 22.3.8
      helm:
        releaseName: "{{path.filename}}"
        valueFiles:
          - $path/app-of-apps/apps/edc/{{path.basename}}/{{path.filename}}
    - repoURL: ${REPO_URL}
      targetRevision: main
      ref: path
```

And finally add the ApplicationSet to ***kustomization.yaml*** under the environment in which we are deploying the app, so that ArgoCD can discover it:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namePrefix: prod-
resources:
  - nginx.yaml
  - nginx-helm.yaml
  - edc.yaml  <-
```

This will create an ArgoCD Application for every values file found in `app-of-apps/apps/edc/cluster-prod`, deploying a release with the name of the file.

```sh
apps/edc/cluster-prod/
├── bblocks-nginx.yaml
└── dsf-nginx.yaml
```

## Tips

### Alias

In order to switch contexts easily you can use the following alias

```sh
alias kgc='kubectl config get-contexts'
alias kuc='kubectl config use-context'
```

### Check with k9s

If you want to check more than one context at the same time:

```sh
k9s --context cluster-dev
k9s --context cluster-prod
```

If you don't have k9s:

- [k9s-install](https://k9scli.io/topics/install/)

## Remove

In order to remove all local clusters created you can run `remove.sh`

> [!NOTE]
> This does not remove `.minikube` or the docker images pulled by minikube

## References

- [ArgoCD Application Docs](https://argo-cd.readthedocs.io/en/latest/user-guide/application-specification/)
- [ArgoCD Helm](https://argo-cd.readthedocs.io/en/release-2.7/user-guide/helm/)
- [Helm value files from external Git repository](https://argo-cd.readthedocs.io/en/release-2.7/user-guide/multiple_sources/#helm-value-files-from-external-git-repository)
- [ArgoCD AppSet Git Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Git/)
