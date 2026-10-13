# aws-kubectl Docker Image

[![ECR Public](https://img.shields.io/badge/ECR_Public-grasshopper%2Faws--kubectl-FF9900?logo=amazon-aws)](https://gallery.ecr.aws/grasshopper/aws-kubectl)
[![Build Status](https://github.com/grasshopper-labs/aws-kubectl-docker/actions/workflows/publish.yml/badge.svg?branch=main)](https://github.com/grasshopper-labs/aws-kubectl-docker/actions/workflows/publish.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/grasshopper-labs/aws-kubectl-docker/badge)](https://scorecard.dev/viewer/?uri=github.com/grasshopper-labs/aws-kubectl-docker)
[![Cosign Verified](https://img.shields.io/badge/cosign-verified-brightgreen?logo=sigstore)](https://github.com/grasshopper-labs/aws-kubectl-docker/attestations)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/14920/badge)](https://www.bestpractices.dev/projects/14920)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Contents

- [aws-kubectl Docker Image](#aws-kubectl-docker-image)
  - [Contents](#contents)
  - [Why this image?](#why-this-image)
  - [Prerequisites](#prerequisites)
  - [Getting started](#getting-started)
  - [Pinning guidance](#pinning-guidance)
  - [Features](#features)
    - [Typical use cases](#typical-use-cases)
  - [Supply chain](#supply-chain)
    - [Verifying signatures](#verifying-signatures)
  - [Tag management](#tag-management)
  - [Breaking Changes in v2.0](#breaking-changes-in-v20)
    - [For most users: no changes needed](#for-most-users-no-changes-needed)
    - [For users mounting volumes](#for-users-mounting-volumes)
    - [Staying on v1.x](#staying-on-v1x)
  - [Mounting credentials](#mounting-credentials)
  - [Running the Container](#running-the-container)
    - [Execute commands directly (no shell)](#execute-commands-directly-no-shell)
  - [Build Instructions](#build-instructions)
    - [Local single-arch (dev)](#local-single-arch-dev)
    - [Pin a specific kubectl](#pin-a-specific-kubectl)
    - [Stamp revision and build date (recommended for release builds)](#stamp-revision-and-build-date-recommended-for-release-builds)
    - [Multi-arch build \& push (amd64 + arm64)](#multi-arch-build--push-amd64--arm64)
  - [Local Build \& Test (using the repo script)](#local-build--test-using-the-repo-script)
    - [Optional “real” checks (with mounted config)](#optional-real-checks-with-mounted-config)
  - [Security Notes](#security-notes)
  - [Run as root (override)](#run-as-root-override)
  - [Standardization reference](#standardization-reference)
  - [About the maintainer](#about-the-maintainer)

This image bundles AWS CLI v2 (`aws`) and kubectl on Ubuntu 26.04. It also includes `jq`, `curl`, `unzip`, and `envsubst` (from `gettext-base`). Perfect for CI/CD steps, automation, and reproducible local scripting.

Image: [`public.ecr.aws/grasshopper/aws-kubectl`](https://gallery.ecr.aws/grasshopper/aws-kubectl)

## Why this image?

| Need | This image | `amazon/aws-cli` | `bitnami/kubectl` | Alpine + scripts |
|------|-----------|------------------|-------------------|------------------|
| AWS CLI v2 | ✅ | ✅ | ❌ | manual |
| kubectl | ✅ | ❌ | ✅ | manual |
| jq, envsubst, curl, unzip | ✅ | ❌ | ❌ | manual |
| Multi-arch (amd64/arm64) | ✅ | ✅ | ✅ | depends |
| Cosign signatures | ✅ | ✅ | ❌ | ❌ |
| SBOM (SPDX) | ✅ | ❌ | ❌ | ❌ |
| SLSA build provenance | ✅ | ❌ | ❌ | ❌ |
| OpenSSF Scorecard | 8.1/10 (as of 2026-10-06) | N/A | N/A | N/A |
| Non-root default (UID 10001) | ✅ (v2.0+) | ❌ | ❌ | depends |
| Weekly base rebuild | ✅ | ✅ | ✅ | manual |

One image instead of three. Full supply-chain attestations. OpenShift-compatible out of the box.

## Prerequisites

- **Docker installed locally.** Quick check: `docker version`. The image ships AWS CLI v2 and `kubectl` inside, so you don't need either installed on your host. Multi-arch (amd64 + arm64): works on Linux, macOS (Intel + Apple Silicon), Windows + WSL2.
- **(Optional) AWS credentials in `~/.aws/`** if you want to run AWS commands. Create with `aws configure` from any machine that has aws-cli, or copy from an existing setup. The image mounts the dir read-only by convention.
- **(Optional) `kubeconfig` in `~/.kube/`** if you want to run `kubectl` commands against an existing cluster. Create with `aws eks update-kubeconfig --name <cluster>` or your tool of choice.

You can also run the container with no mounts for `aws --version`, `kubectl version --client`, or any tool that doesn't need cloud/cluster credentials.

## Getting started

```bash
# List S3 buckets (requires ~/.aws)
docker run --rm --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  public.ecr.aws/grasshopper/aws-kubectl aws s3 ls

# Get Kubernetes nodes (requires ~/.kube)
docker run --rm --user "$(id -u):0" \
  -v ~/.kube:/home/app/.kube \
  public.ecr.aws/grasshopper/aws-kubectl kubectl get nodes

# Interactive shell with both
docker run -it --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  -v ~/.kube:/home/app/.kube \
  public.ecr.aws/grasshopper/aws-kubectl bash
```

Runs as non-root by default (UID 10001). See [Mounting credentials](#mounting-credentials) for permission details.

> 🚨 Existing v1.x user? The `v1-maintenance` tag reached end of support on 2026-07-20 and was last rebuilt on 2026-04-22; it gets no further updates. [Migration details →](#breaking-changes-in-v20)

## Pinning guidance

For production use, pin to an exact semver tag. The publish job will not move an exact semver tag, a `sha-*` tag, or a `kube-*` tag that already exists. ECR Public does not enforce that itself.

- ✅ Stable: `public.ecr.aws/grasshopper/aws-kubectl:<version>` (for example `:2.2.1` once that release is published from this repository). Cosign-signed. Not moved after the first push.
- ⚠️ Rolling: `:2` and `:2.2` move to the newest matching release. `:latest` and `:edge` move on every build of `main`, including the weekly rebuild.
- ⚠️ Fragile: `public.ecr.aws/grasshopper/aws-kubectl:sha-1dfda81`. A short-SHA tag is removed after 90 days only when it is the only tag on its digest.

Tags that were published on Docker Hub as `heyvaldemar/aws-kubectl` are not copied into this registry. That includes the unsigned `2.2.0` / `v2.2.0` / `kube-v1.37.1` digest and the frozen `v1-maintenance` tag.

If you pin by manifest digest, make sure a semver tag still points at it. A digest whose only tag was `sha-*` can be deleted after 90 days. To resolve a tag to its current digest:

```bash
docker buildx imagetools inspect public.ecr.aws/grasshopper/aws-kubectl:latest \
  --format '{{.Manifest.Digest}}'
```

## Features

- **Ubuntu 26.04** base since 2.1.0 (2.0.0 runs Ubuntu 24.04).
- **AWS CLI v2** for full AWS management.
- **kubectl** (pin a specific version or use the latest stable at build time).
- `jq`, `curl`, `unzip`, `envsubst`, and `ca-certificates` preinstalled.
- **Multi-stage build**: build-only intermediates (AWS CLI zip, extracted tree, kubectl archive) never enter the final image.
- **Checksum verification** for `kubectl` during build.
- **Multi-arch ready** (amd64/arm64) when built/pushed with `buildx`.
- **OCI labels** (`org.opencontainers.image.*`) on every published image.
- **Resolved kubectl version** written to `/etc/kube-version` inside the image.

> Default user is non-root (UID 10001, GID 0) as of v2.0. If you need root (e.g. to install additional `apt` packages at runtime), override with `--user 0:0`. See [Breaking Changes in v2.0](#breaking-changes-in-v20) for migration details.

### Typical use cases

- **GitHub Actions / GitLab CI pipelines**: one image instead of installing aws-cli + kubectl + jq separately in every job
- **EKS cluster operations**: AWS auth via aws-cli, then kubectl against the cluster, in a single container
- **OpenShift / Pod Security Admission `restricted` namespaces**: the non-root default (UID 10001, GID 0) meets `runAsNonRoot`; the pod spec sets the rest of the `restricted` profile (`allowPrivilegeEscalation: false`, drop `ALL` capabilities, `RuntimeDefault` seccomp)
- **Multi-cluster scripting**: consistent tooling across dev/staging/prod kubeconfigs
- **Air-gapped or restricted networks**: pre-built image, no runtime `curl | bash`. kubectl is checksum-verified at build time; the AWS CLI installer is downloaded from AWS over TLS without a signature check

## Supply chain

- Base image pinned by `sha256` digest (`ubuntu:26.04@sha256:…`). The digest moves only when a pull request changes it. Dependabot's `docker` updates were switched off on 2026-09-06, so the base is bumped by hand; the pinned digest dates from 2026-09-02.
- Multi-stage `Dockerfile` keeps build-only intermediate artefacts (the downloaded AWS CLI archive, extracted tree, kubectl tarball, and checksum file) out of the published image.
- `kubectl` binaries are verified against the upstream `sha256` checksum published at `dl.k8s.io` during build.
- Weekly scheduled rebuilds (`cron: "0 6 * * 1"`) reinstall the packages the image adds on top of the base from the current Ubuntu archive, and fetch the current stable kubectl and AWS CLI. They do not move the pinned base layers; that takes a digest bump.
- CI lints the Dockerfile with `hadolint` and shell scripts with `shellcheck` before any build runs.
- Every third-party GitHub Action is pinned to a commit SHA with a version comment, with one exception: `release-assets.yml` calls the SLSA generator's reusable workflow by tag (`@v2.1.0`), because the generator verifies its own reference at run time and refuses a SHA. OpenSSF Scorecard counts that line against Pinned-Dependencies.
- Build arguments `VCS_REF` and `BUILD_DATE` are stamped into `org.opencontainers.image.revision` and `org.opencontainers.image.created`, and the resolved kubectl release is exposed via `io.heyvaldemar.kubectl.version` and `/etc/kube-version`.
- Every digest this workflow publishes is cosign-signed via Sigstore keyless OIDC using the GitHub Actions identity for this repository. The unsigned Docker Hub tags `2.2.0`, `v2.2.0`, and `kube-v1.37.1` were not copied here.
- **SBOM** (SPDX, generated by BuildKit) and SLSA build provenance (`provenance: mode=max`) are attached to every published image.
- **GitHub native build provenance** is attested via `actions/attest-build-provenance` and stored in [GitHub Attestations](https://github.com/grasshopper-labs/aws-kubectl-docker/attestations). It is not pushed to ECR Public: the job that creates it has no registry credentials. BuildKit's SBOM and provenance travel inside the image index that is pushed.
- **Trivy** scans the published image on every push; CRITICAL and HIGH fixable findings are uploaded as SARIF to the repository's GitHub Security tab.

### Verifying signatures

```bash
cosign verify public.ecr.aws/grasshopper/aws-kubectl:latest \
  --certificate-identity-regexp "https://github.com/grasshopper-labs/aws-kubectl-docker/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

## Tag management

Tags fall into five categories:

- **Exact semver** (`:2.0.0`, `:v2.0.0`): the publish job will not move the tag once it exists. Recommended for production pins.
- **Rolling semver** (`:2.0`, `:2`): mutable; re-targets to the newest patch (and minor) within the major on each release. Kept forever.
- **Floating channels** (`:latest`, `:edge`): updated on every main build and by the weekly rebuild; kept forever. `:v1-maintenance` is not published to this registry; on Docker Hub it is frozen at its 2026-04-22 build (end of support 2026-07-20).
- **Kubernetes-version pin** (`:kube-v1.36.0`): generated only on semver releases. Tracks the kubectl release packaged into the image at the time of that release. Not moved once it exists.
- **Short-SHA builds** (`:sha-<7char>`): produced by CI for every commit to main. Not moved while the tag exists. A digest whose tags are all `sha-*` and older than 90 days is deleted by the `ECR Public tag cleanup` workflow. A `sha-*` tag that shares its digest with another tag is kept, because ECR Public deletes the image, not one tag.

Cosign signatures (`:sha256-<digest>.sig`) are managed by Sigstore and are not deleted. The cleanup treats `sha256-` as a signature tag, not a short SHA.

## Breaking changes in v2.0

Starting with v2.0.0, this image runs as a non-root user (UID 10001, GID 0)
by default. This is how hardened container images are built today, and it is
required for compatibility with OpenShift, the Kubernetes Pod Security Standards
`restricted` profile (enforced by Pod Security Admission; PodSecurityPolicy was
removed in Kubernetes 1.25), and enterprise security scanners.

### For most users: no changes needed

If you use this image for one-off CI commands (`aws s3 sync`, `kubectl apply`),
v2.0 works identically to v1.x.

### For users mounting volumes

If you mount a host directory or Kubernetes PVC, you may need to adjust file
ownership or run the container with a matching UID:

**Docker:**

```bash
docker run --rm -v "$PWD:/home/app" --user "$(id -u):0" \
  public.ecr.aws/grasshopper/aws-kubectl:latest aws s3 ls
```

**Kubernetes:**

```yaml
spec:
  securityContext:
    runAsUser: 10001
    runAsGroup: 0
    fsGroup: 0
```

### Staying on v1.x

If v2.0 breaks your workflow and you need time to migrate, pin to the v1
maintenance track:

```bash
docker pull heyvaldemar/aws-kubectl:v1-maintenance
```

That tag was published on Docker Hub only. It is not in
`public.ecr.aws/grasshopper/aws-kubectl`. It reached end of support on
July 20, 2026. Its last rebuild was on April 22, 2026, so it received no
security updates between that date and the end of support, and it is now
frozen. Pin it only while you migrate to a 2.x tag on ECR Public.

## Mounting credentials

- `~/.aws` – AWS credentials/config (`credentials`, `config`). Mount to `/home/app/.aws` inside the container.
- `~/.kube` – kubeconfig(s). Mount to `/home/app/.kube` inside the container.

> The container's default user is UID 10001 with `HOME=/home/app`. Pass `--user "$(id -u):0"` when mounting host files so the container can read them.

## Running the container

Interactive shell with both configs (mount under `/home/app`, the non-root user's `HOME`, and match your host UID so the container can read the mounted files):

```bash
docker run -it \
  --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  -v ~/.kube:/home/app/.kube \
  public.ecr.aws/grasshopper/aws-kubectl bash
```

If you pulled an amd64-only tag on an ARM/M-series Mac:

```bash
docker run --platform linux/amd64 -it \
  --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  -v ~/.kube:/home/app/.kube \
  public.ecr.aws/grasshopper/aws-kubectl bash
```

### Execute commands directly (no shell)

```bash
# List S3 buckets
docker run --rm \
  --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  public.ecr.aws/grasshopper/aws-kubectl aws s3 ls

# Get Kubernetes nodes
docker run --rm \
  --user "$(id -u):0" \
  -v ~/.kube:/home/app/.kube \
  public.ecr.aws/grasshopper/aws-kubectl kubectl get nodes
```

## Build instructions

The `Dockerfile` accepts the following build arguments:

| ARG          | Default    | Purpose                                                                  |
|--------------|------------|--------------------------------------------------------------------------|
| `KUBE_VERSION` | `latest` | Pin a specific `kubectl` release (e.g. `v1.30.6`). `latest` fetches the current stable from `dl.k8s.io`. |
| `VCS_REF`      | `unknown`| Commit SHA, stamped into `org.opencontainers.image.revision`.             |
| `BUILD_DATE`   | `unknown`| ISO-8601 build timestamp, stamped into `org.opencontainers.image.created`.|
| `TARGETARCH`   | auto     | Target architecture. CI publishes `amd64` and `arm64` only. AWS CLI v2 has no armv7 or i386 installer, and the build rejects any other architecture. Supplied automatically by `buildx`.|

### Local single-arch (dev)

```bash
# From the folder with the Dockerfile
docker build -t aws-kubectl:local .
```

### Pin a specific kubectl

```bash
docker build --build-arg KUBE_VERSION=v1.30.6 \
  -t aws-kubectl:local .
```

If `KUBE_VERSION` is omitted, the build fetches the latest stable from `dl.k8s.io`.

### Stamp revision and build date (recommended for release builds)

```bash
docker build \
  --build-arg KUBE_VERSION=v1.30.6 \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  -t aws-kubectl:local .
```

### Multi-arch build & push (amd64 + arm64)

CI builds `linux/amd64` and `linux/arm64` on GitHub-hosted runners and pushes the index from a self-hosted runner. `linux/arm/v7` is not included: the Ubuntu 26.04 base publishes it, and does not publish `linux/386`, but AWS CLI v2 ships installers only for x86_64 and aarch64.

A manual push to the same registry needs an ECR Public login in `us-east-1` (the only region for that API). The repository must already exist.

```bash
aws ecr-public get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin public.ecr.aws

docker buildx create --name x --use || docker buildx use x

# Generic tag (no OS name in the tag)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  -t public.ecr.aws/grasshopper/aws-kubectl:latest \
  --push .

# Or pin kubectl in a tag users can reason about
KUBE_VERSION=v1.30.6
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg KUBE_VERSION=$KUBE_VERSION \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  -t public.ecr.aws/grasshopper/aws-kubectl:kube-$KUBE_VERSION \
  --push .
```

Verify:

```bash
docker buildx imagetools inspect public.ecr.aws/grasshopper/aws-kubectl:latest
```

> Optional supply-chain flags (if you want SBOM/provenance):
> `--sbom=true --provenance=true`

## Local build & test (using the repo script)

This repo includes `scripts/smoke-test.sh` to validate the tools in the image. CI runs it on every push and pull request against an image built from the commit, before anything is published: the publish job waits for it. It also checks that the image runs as UID 10001 with a writable `HOME`, and [`tests/plant-violations.py`](tests/plant-violations.py) proves the test can fail by rebuilding the image with each promise broken, five ways listed in [`tests/plants.tsv`](tests/plants.tsv): running as root, jq or envsubst left out, the version marker not matching kubectl, and `HOME` left unwritable.

1. **Build locally**

```bash
docker build -t aws-kubectl:local .
```

2. **Run the smoke test**

```bash
chmod +x scripts/smoke-test.sh
./scripts/smoke-test.sh                # defaults to aws-kubectl:local
./scripts/smoke-test.sh your/tag:dev   # test any tag you pass
```

The script checks:

- OS/arch
- Versions: AWS CLI, kubectl (client), jq, envsubst, curl, unzip
- That `/etc/kube-version` matches `kubectl version --client`
- That the image runs as UID 10001, GID 0, with a writable `HOME=/home/app`
- Binary locations & CA bundle
- HTTPS reachability (header-only)
- (Optional) AWS STS + `kubectl` cluster calls if you mount `~/.aws` / `~/.kube`

<details>
<summary>Quick verification one-liners (click to expand)</summary>

```bash
IMG=aws-kubectl:local

# OS/arch
docker run --rm $IMG sh -lc 'uname -a; echo -n "Arch: "; uname -m'

# Core tools & versions
docker run --rm $IMG aws --version
docker run --rm $IMG kubectl version --client --output=yaml
docker run --rm $IMG jq --version
docker run --rm $IMG envsubst --version
docker run --rm $IMG sh -c 'curl --version | head -n1'
docker run --rm $IMG sh -c 'unzip -v | head -n2'

# Resolved kubectl release stamped at build time
docker run --rm $IMG cat /etc/kube-version

# Binaries present where expected
docker run --rm $IMG sh -c 'ls -l /usr/local/bin/kubectl; for b in aws jq envsubst curl unzip; do command -v "$b"; done'

# CA bundle present + HTTPS sanity
docker run --rm $IMG sh -c 'ls -lh /etc/ssl/certs/ca-certificates.crt'
docker run --rm $IMG sh -c 'curl -fsSI -o /dev/null -w "HTTPS OK (%{http_code})\n" https://kubernetes.io'
```

### Optional “real” checks (with mounted config)

```bash
# AWS identity (requires valid creds)
docker run --rm --user "$(id -u):0" \
  -v ~/.aws:/home/app/.aws \
  aws-kubectl:local aws sts get-caller-identity

# Current k8s context & nodes (requires valid kubeconfig)
docker run --rm --user "$(id -u):0" \
  -v ~/.kube:/home/app/.kube \
  aws-kubectl:local kubectl config current-context

docker run --rm --user "$(id -u):0" \
  -v ~/.kube:/home/app/.kube \
  aws-kubectl:local kubectl get nodes -o wide
```

</details>

## Security notes

- Runs as non-root by default (UID 10001, GID 0) as of v2.0.
- `kubectl` binaries are checksum-verified during build.
- APT is minimal (`--no-install-recommends`) and lists are cleaned.
- Pin `KUBE_VERSION` in CI for reproducibility.

## Run as root (override)

If a specific workflow requires root inside the container (e.g. installing additional `apt` packages at runtime, or restoring pre-v2.0 behaviour), override the user:

```bash
docker run --rm --user 0:0 public.ecr.aws/grasshopper/aws-kubectl bash
```

## Standardization reference

The patterns in this image are codified as a reusable standard at [`heyvaldemar/self-host-repo-hardening-runbook` → `IMAGE-PUBLISHING-RUNBOOK.md`](https://github.com/heyvaldemar/self-host-repo-hardening-runbook/blob/main/IMAGE-PUBLISHING-RUNBOOK.md). If you maintain a Dockerfile-based repo and want to follow the same standard, the runbook covers:

- Multi-stage Dockerfile with base-image digest pinning
- Full OCI labels (`org.opencontainers.image.*`)
- BuildKit attestations (SBOM + SLSA `provenance: mode=max`)
- Cosign keyless signing via Sigstore (with rationale for pinning Cosign v2.6.1 over v3.x)
- Tag retention. Exact semver, `sha-*`, and `kube-*` are not moved after the first push; sha-only digests older than 90 days are deleted
- Weekly base-image rebuild via cron
- Pinning guidance documentation for downstream consumers

Six mandatory phases plus an optional non-root migration phase for repos with existing `:latest` audiences. Eight production-grounded pitfalls drawn from this repo's own PR history.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** — Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>