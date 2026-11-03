#!/usr/bin/env python3
"""Update the manifests from a published OpenTubeX release.

Usage: update.py [TAG]

Without a tag, the latest stable release is used. Stable releases update both
manifests; nightly releases update only the nightly manifest.
"""

import copy
import json
from pathlib import Path
import re
import subprocess
import sys


BUCKET = Path(__file__).resolve().parents[1] / "bucket"
STABLE = BUCKET / "opentubex.json"
NIGHTLY = BUCKET / "opentubex-nightly.json"
TAG = re.compile(r"v(\d+)\.(\d+)\.(\d+)(-beta|-nightly-(\d+))?")
ARCHITECTURES = {"64bit": "x64", "arm64": "arm64"}


def version_key(version):
    match = TAG.fullmatch(f"v{version}")
    if match is None:
        raise ValueError(f"Unexpected version: {version}")
    major, minor, patch, suffix, nightly = match.groups()
    # Betas precede the final release. Nightlies follow the release they are numbered after.
    rank = (2, int(nightly)) if nightly else (0, 0) if suffix else (1, 0)
    return (int(major), int(minor), int(patch), *rank)


def update(manifest, release, nightly=False):
    tag = release["tagName"]
    match = TAG.fullmatch(tag)
    if release["isDraft"] or match is None:
        raise ValueError(f"Unexpected release tag: {tag}")
    is_nightly = match[5] is not None
    if release["isPrerelease"] != is_nightly:
        raise ValueError(f"Release type does not match tag: {tag}")
    if is_nightly and not nightly:
        raise ValueError("Only published stable releases can update the stable manifest")
    if set(manifest.get("architecture", {})) != set(ARCHITECTURES):
        raise ValueError("Unexpected manifest architectures")
    version = tag[1:]

    if version_key(version) < version_key(manifest["version"]):
        if nightly:
            # The nightly manifest already follows a newer build.
            return manifest
        raise ValueError("Refusing to downgrade the manifest")

    updated = copy.deepcopy(manifest)
    updated["version"] = version
    for key, arch in ARCHITECTURES.items():
        name = f"opentubex-{version}-win-{arch}-portable.zip"
        matches = [asset for asset in release["assets"] if asset["name"] == name]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one release asset: {name}")
        asset = matches[0]
        url = f"https://github.com/OpenTubeX/OpenTubeX/releases/download/{tag}/{name}"
        if asset["url"] != url or asset["state"] != "uploaded":
            raise ValueError(f"Unexpected or incomplete asset: {name}")
        digest = asset.get("digest") or ""
        if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
            raise ValueError(f"Missing SHA-256 digest: {name}")
        updated["architecture"][key] = {"url": url, "hash": digest[7:]}
    return updated


if __name__ == "__main__":
    result = subprocess.run(
        ["gh", "release", "view", *sys.argv[1:2], "--repo", "OpenTubeX/OpenTubeX",
         "--json", "tagName,isDraft,isPrerelease,assets"],
        check=True, capture_output=True, text=True,
    )
    release = json.loads(result.stdout)
    manifests = [(NIGHTLY, True)] if release["isPrerelease"] else [(STABLE, False), (NIGHTLY, True)]
    for path, nightly in manifests:
        source = path.read_text()
        updated = json.dumps(update(json.loads(source), release, nightly), indent=4) + "\n"
        if updated != source:
            path.write_text(updated)
            print(f"Updated {path.name}")
        else:
            print(f"{path.name} is current")
