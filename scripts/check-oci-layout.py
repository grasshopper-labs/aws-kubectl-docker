#!/usr/bin/env python3
"""Confirm a buildx OCI layout tar's index.json is one multi-arch index.

The push job uses ``crane push`` without ``--index``, which publishes the
single descriptor in index.json. That descriptor's digest is what ECR Public
and cosign must both see. Prints the digest on stdout.
"""

import json
import os
import sys


def evaluate(index, expected):
    manifests = index.get("manifests") or []
    if len(manifests) != 1:
        return None, (
            f"OCI layout index.json has {len(manifests)} entries; "
            "the push job expects exactly one"
        )
    digest = manifests[0].get("digest") or ""
    media = manifests[0].get("mediaType") or ""
    if not digest.startswith("sha256:"):
        return None, f"unexpected layout digest {digest!r}"
    if "index" not in media and "manifest.list" not in media:
        return None, f"layout entry is {media}, want a multi-arch index"
    if expected and expected != digest:
        return None, f"build digest {expected} != layout digest {digest}"
    return digest, None


def self_check():
    good = {
        "manifests": [
            {
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "digest": "sha256:abc",
            }
        ]
    }
    digest, err = evaluate(good, "sha256:abc")
    assert err is None and digest == "sha256:abc", err
    digest, err = evaluate(good, "")
    assert err is None and digest == "sha256:abc", err
    _, err = evaluate(good, "sha256:other")
    assert err and "build digest" in err, err
    _, err = evaluate({"manifests": [{}, {}]}, "")
    assert err and "2 entries" in err, err
    _, err = evaluate(
        {
            "manifests": [
                {
                    "mediaType": "application/vnd.oci.image.manifest.v1+json",
                    "digest": "sha256:abc",
                }
            ]
        },
        "",
    )
    assert err and "multi-arch" in err, err
    print("oci layout check ok")


def main(argv):
    if len(argv) == 2 and argv[1] == "--self-check":
        self_check()
        return 0
    if len(argv) != 2:
        print("usage: check-oci-layout.py INDEX.json", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as fh:
        index = json.load(fh)
    digest, err = evaluate(index, os.environ.get("ACTION_DIGEST", ""))
    if err:
        print(err, file=sys.stderr)
        return 1
    print(digest)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
