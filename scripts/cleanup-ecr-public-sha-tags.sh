#!/usr/bin/env bash
# Delete sha-* images from ECR Public once they are older than 90 days.
#
# ECR Public deletes by image digest, and that removes every tag on the
# digest. This only deletes a digest when every tag on it is sha-<hex>.
# A sha-* tag that still shares its digest with latest, edge, a semver tag,
# or a cosign signature (sha256-*.sig) is left alone.
#
# Assumed already installed: aws CLI v2, bash, GNU date. No jq, no sudo.
# The repository must already exist. API region is us-east-1.
set -euo pipefail

sha_only() {
  local tag
  [[ "$#" -ge 1 ]] || return 1
  for tag in "$@"; do
    [[ "$tag" =~ ^sha-[0-9a-fA-F]+$ ]] || return 1
  done
}

self_check() {
  local fail=0
  expect() {
    local want="$1"
    shift
    local got=no
    if sha_only "$@"; then
      got=yes
    fi
    if [[ "$got" != "$want" ]]; then
      echo "FAIL [$*]: want delete=${want} got=${got}" >&2
      fail=1
    fi
  }
  expect yes sha-1dfda81
  expect yes sha-1dfda81 sha-abcdef0
  expect no latest
  expect no sha-1dfda81 latest
  expect no sha-1dfda81 edge
  expect no sha256-abcdef.sig
  expect no sha-1dfda81 sha256-abcdef.sig
  expect no kube-v1.33.1
  expect no 2.2.1
  if [[ "$fail" -ne 0 ]]; then
    exit 1
  fi
  echo "sha-only classification ok"
}

if [[ "${1:-}" == "--self-check" ]]; then
  self_check
  exit 0
fi

: "${ECR_REPOSITORY:?}"
: "${DRY_RUN:?}"
: "${ECR_REGION:=us-east-1}"

case "$DRY_RUN" in
  true | false) ;;
  *)
    echo "::error::DRY_RUN must be true or false, got: ${DRY_RUN}" >&2
    exit 1
    ;;
esac

export AWS_PAGER=""
cutoff=$(date -u -d '90 days ago' +%s)
echo "Deleting sha-only images pushed before $(date -u -d "@${cutoff}" +%Y-%m-%dT%H:%M:%SZ) (dry_run=${DRY_RUN})"

# aws CLI v2 paginates describe-images on its own.
listing=$(aws ecr-public describe-images \
  --region "$ECR_REGION" \
  --repository-name "$ECR_REPOSITORY" \
  --query 'imageDetails[].[imageDigest,imagePushedAt,imageTags]' \
  --output text)

deleted=0
while IFS=$'\t' read -r digest pushed rest; do
  [[ -z "${digest:-}" ]] && continue
  [[ "$digest" == "None" ]] && continue
  if [[ -z "${rest:-}" || "$rest" == "None" ]]; then
    continue
  fi
  tags=()
  IFS=$'\t' read -r -a tags <<<"$rest"
  if ! sha_only "${tags[@]}"; then
    continue
  fi
  pushed_epoch=$(date -u -d "$pushed" +%s)
  if [[ "$pushed_epoch" -ge "$cutoff" ]]; then
    continue
  fi
  echo "sha-only and old: ${digest} (${rest//$'\t'/, })"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] would delete ${digest}"
    continue
  fi
  failures=$(aws ecr-public batch-delete-image \
    --region "$ECR_REGION" \
    --repository-name "$ECR_REPOSITORY" \
    --image-ids "imageDigest=${digest}" \
    --query 'length(failures)' \
    --output text)
  if [[ "$failures" != "0" ]]; then
    echo "::error::ECR Public refused to delete ${digest}" >&2
    exit 1
  fi
  deleted=$((deleted + 1))
done <<<"$listing"

echo "Deleted ${deleted} image(s)"
