#!/usr/bin/env bash
# Push a buildx OCI layout to ECR Public and sign it.
#
# The GitHub-hosted build job uploads one OCI layout tar (linux/amd64 and
# linux/arm64, plus the BuildKit attestations). This script runs where the AWS
# credentials are: the ecr-public-publisher pod's IAM role (IRSA or pod
# identity). It does not read AWS keys from the environment.
#
# Assumed already installed: docker, aws CLI v2, curl, tar, sha256sum, bash.
# Installed here, into a temp directory, after a checksum check: crane v0.22.1
# and cosign v2.6.1. No sudo. crane and cosign are static binaries.
#
# ECR Public's API is only in us-east-1. The repository must already exist in
# the account that owns the public alias; this script does not create it.
set -euo pipefail

CRANE_VERSION=v0.22.1
# sha256 of the upstream go-containerregistry release tarballs.
CRANE_SHA_X86_64=0ab7a1d6932a213aed964ce97666c3077fe691c8606413674a8b3e0b9ec4cda0
CRANE_SHA_ARM64=898c0cff975f898a33e8c4580bdafb0e7c02c7faa33374e946762f97c4ab7110

# Cosign v2.6.1 keeps tag-based signatures. v3 stores them as OCI 1.1 referrers,
# which this registry path has not been tried with.
COSIGN_VERSION=v2.6.1
COSIGN_SHA_X86_64=064954c5d8c7e3b28188eee5b1727b31c411550bc5fefd41aa672d3c761d103a
COSIGN_SHA_ARM64=56a16480bdd56ec789abaa65924402f6b92c0041f06885995853c05567b76f34

# Exact release tags and the short-SHA / kubectl pins stay where they are.
# Rolling tags (latest, edge, 2, 2.2) are updated. ECR Public does not
# enforce that; this script does.
tag_is_immutable() {
  local name="$1"
  case "$name" in
    sha-* | kube-*) return 0 ;;
  esac
  [[ "$name" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]
}

self_check() {
  local fail=0
  expect() {
    local name="$1" want="$2" got=no
    if tag_is_immutable "$name"; then
      got=yes
    fi
    if [[ "$got" != "$want" ]]; then
      echo "FAIL ${name}: want immutable=${want} got=${got}" >&2
      fail=1
    fi
  }
  expect latest no
  expect edge no
  expect 2 no
  expect 2.2 no
  expect 2.2.1 yes
  expect v2.2.1 yes
  expect 2.2.1-rc1 yes
  expect v2.2.1-rc.1 yes
  expect sha-1dfda81 yes
  expect sha256-abcdef.sig no
  expect kube-v1.33.1 yes
  if [[ "$fail" -ne 0 ]]; then
    exit 1
  fi
  echo "tag classification ok"
}

if [[ "${1:-}" == "--self-check" ]]; then
  self_check
  exit 0
fi

: "${IMAGE_NAME:?}"
: "${ECR_REPOSITORY:?}"
: "${OCI_TAR:?}"
: "${TAGS:?}"
: "${EXPECTED_DIGEST:?}"
: "${ECR_REGION:=us-east-1}"

if [[ ! -f "$OCI_TAR" ]]; then
  echo "::error::OCI archive not found: ${OCI_TAR}" >&2
  exit 1
fi
if [[ "$EXPECTED_DIGEST" != sha256:* ]]; then
  echo "::error::EXPECTED_DIGEST must be a sha256 digest, got: ${EXPECTED_DIGEST}" >&2
  exit 1
fi

# A runner with a pager configured would block on describe-images.
export AWS_PAGER=""
export AWS_CLI_AUTO_PROMPT=off

install_tools() {
  local bin arch asset sum url tmp
  bin=$(mktemp -d)
  case "$(uname -m)" in
    x86_64)
      arch=x86_64
      sum="$CRANE_SHA_X86_64"
      ;;
    aarch64 | arm64)
      arch=arm64
      sum="$CRANE_SHA_ARM64"
      ;;
    *)
      echo "::error::no pinned crane/cosign binary for $(uname -m)" >&2
      exit 1
      ;;
  esac

  tmp=$(mktemp -d)
  asset="go-containerregistry_Linux_${arch}.tar.gz"
  url="https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/${asset}"
  curl -fsSL --retry 5 --retry-delay 2 -o "${tmp}/${asset}" "$url"
  echo "${sum}  ${tmp}/${asset}" | sha256sum -c - >&2
  tar -xzf "${tmp}/${asset}" -C "$tmp" crane
  cp "${tmp}/crane" "${bin}/crane"
  chmod 0755 "${bin}/crane"

  case "$arch" in
    x86_64) sum="$COSIGN_SHA_X86_64" ;;
    arm64) sum="$COSIGN_SHA_ARM64" ;;
  esac
  url="https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-${arch}"
  curl -fsSL --retry 5 --retry-delay 2 -o "${bin}/cosign" "$url"
  echo "${sum}  ${bin}/cosign" | sha256sum -c - >&2
  chmod 0755 "${bin}/cosign"

  echo "$bin"
}

tag_exists() {
  local name="$1" err rc
  set +e
  err=$(aws ecr-public describe-images \
    --region "$ECR_REGION" \
    --repository-name "$ECR_REPOSITORY" \
    --image-ids "imageTag=${name}" \
    --query 'imageDetails[0].imageDigest' \
    --output text 2>&1)
  rc=$?
  set -e
  if [[ "$rc" -eq 0 && -n "$err" && "$err" != "None" ]]; then
    return 0
  fi
  if [[ "$err" == *ImageNotFoundException* ]]; then
    return 1
  fi
  echo "::error::cannot tell whether ${name} exists: ${err}" >&2
  exit 1
}

mutable=()
immutable=()
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  case "$ref" in
    "${IMAGE_NAME}:"*) ;;
    *)
      echo "::error::refuses to publish unexpected reference: ${ref}" >&2
      exit 1
      ;;
  esac
  name="${ref##*:}"
  if [[ ! "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    echo "::error::refuses tag name: ${name}" >&2
    exit 1
  fi
  if tag_is_immutable "$name" && tag_exists "$name"; then
    echo "Leaving existing immutable tag ${name} in place"
    continue
  fi
  if tag_is_immutable "$name"; then
    immutable+=("$name")
  else
    mutable+=("$name")
  fi
done <<<"$TAGS"

# Mutable tags go first so a bad push cannot stick an immutable tag to the
# wrong digest. A failed job can republish latest/edge; it cannot move 2.2.1.
publish=()
if [[ ${#mutable[@]} -gt 0 ]]; then
  publish+=("${mutable[@]}")
fi
if [[ ${#immutable[@]} -gt 0 ]]; then
  publish+=("${immutable[@]}")
fi

if [[ ${#publish[@]} -eq 0 ]]; then
  echo "Every tag already exists and is immutable; nothing to push"
  exit 0
fi

TOOL_BIN=$(install_tools)
export PATH="${TOOL_BIN}:${PATH}"

# Keep the token out of the runner's default Docker config. crane and cosign
# both read DOCKER_CONFIG.
export DOCKER_CONFIG="${RUNNER_TEMP:-/tmp}/ecr-public-docker-config"
mkdir -p "$DOCKER_CONFIG"
aws ecr-public get-login-password --region "$ECR_REGION" |
  docker login --username AWS --password-stdin public.ecr.aws

layout=$(mktemp -d)
tar -xf "$OCI_TAR" -C "$layout"
if [[ ! -f "${layout}/index.json" || ! -f "${layout}/oci-layout" ]]; then
  echo "::error::${OCI_TAR} is not an OCI layout archive" >&2
  exit 1
fi

anchor="${publish[0]}"
echo "Pushing ${IMAGE_NAME}:${anchor}"
errfile=$(mktemp)
if ! pushed=$(crane push "$layout" "${IMAGE_NAME}:${anchor}" 2>"$errfile"); then
  cat "$errfile" >&2
  if grep -q 'consider --index' "$errfile"; then
    echo "::error::OCI layout is not the single-index archive this job expects" >&2
  fi
  exit 1
fi
cat "$errfile" >&2

got=""
while IFS= read -r line; do
  [[ -n "$line" ]] && got="$line"
done <<<"$pushed"
got="${got##*@}"
if [[ "$got" != "$EXPECTED_DIGEST" ]]; then
  echo "::error::pushed ${got}, build recorded ${EXPECTED_DIGEST}" >&2
  exit 1
fi
echo "Pushed ${IMAGE_NAME}@${got}"

for name in "${publish[@]:1}"; do
  echo "Tagging ${name}"
  crane tag "${IMAGE_NAME}:${anchor}" "$name"
done

echo "Signing ${IMAGE_NAME}@${EXPECTED_DIGEST}"
cosign sign --yes "${IMAGE_NAME}@${EXPECTED_DIGEST}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### ECR Public"
    echo
    echo "\`${IMAGE_NAME}@${EXPECTED_DIGEST}\`"
    echo
    for name in "${publish[@]}"; do
      echo "- \`${IMAGE_NAME}:${name}\`"
    done
  } >>"$GITHUB_STEP_SUMMARY"
fi
