#!/usr/bin/env bash
# Put a pinned AWS CLI v2 on PATH when the host does not already have one.
#
# Used by the ecr-public-publisher jobs. That runner has docker and the usual
# shell tools, but not aws. No sudo: the official installer lands in a temp
# directory. Prefer unzip; fall back to python3 (zipfile drops exec bits).
#
# Source this file, then call ensure_aws_cli. Safe under set -euo pipefail.
# shellcheck shell=bash

AWS_CLI_VERSION=2.37.13
# sha256 of https://awscli.amazonaws.com/awscli-exe-linux-<arch>-${AWS_CLI_VERSION}.zip
AWS_CLI_SHA_X86_64=c92fde59827622889d3d38a44e2089a137894ce151a2c658a3988ecde4860caa
AWS_CLI_SHA_AARCH64=f937a72a824c25f8cf38ff4249257c96840578c7eaea1d29117cdc249cbd3ebe

ensure_aws_cli() {
  if command -v aws >/dev/null 2>&1; then
    return 0
  fi

  local arch sum url tmp bin
  case "$(uname -m)" in
    x86_64)
      arch=x86_64
      sum="$AWS_CLI_SHA_X86_64"
      ;;
    aarch64 | arm64)
      arch=aarch64
      sum="$AWS_CLI_SHA_AARCH64"
      ;;
    *)
      echo "::error::no pinned AWS CLI installer for $(uname -m)" >&2
      return 1
      ;;
  esac

  tmp=$(mktemp -d)
  bin=$(mktemp -d)
  url="https://awscli.amazonaws.com/awscli-exe-linux-${arch}-${AWS_CLI_VERSION}.zip"
  curl -fsSL --retry 5 --retry-delay 2 -o "${tmp}/awscliv2.zip" "$url"
  echo "${sum}  ${tmp}/awscliv2.zip" | sha256sum -c - >&2

  if command -v unzip >/dev/null 2>&1; then
    unzip -q "${tmp}/awscliv2.zip" -d "$tmp"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
      "${tmp}/awscliv2.zip" "$tmp"
    # zipfile does not restore executable bits the installer needs.
    chmod -R u+rx "${tmp}/aws/dist" "${tmp}/aws/install"
  else
    echo "::error::need unzip or python3 to unpack the AWS CLI installer" >&2
    return 1
  fi

  "${tmp}/aws/install" -i "${tmp}/aws-cli" -b "$bin" >&2
  export PATH="${bin}:${PATH}"
  command -v aws >/dev/null 2>&1 || {
    echo "::error::AWS CLI install finished but aws is not on PATH" >&2
    return 1
  }
}
