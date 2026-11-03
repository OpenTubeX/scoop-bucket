# OpenTubeX Scoop bucket

This repository distributes [OpenTubeX](https://github.com/OpenTubeX/OpenTubeX)
through [Scoop](https://scoop.sh/) on Windows. It supports x64 and ARM64.

The packages use the files from the official portable ZIP releases. Scoop
removes the portable mode files during installation, so OpenTubeX runs as a
regular app with notifications and `opentubex://` links.

## Install OpenTubeX

With Scoop installed, add the bucket and install the stable release:

```powershell
scoop bucket add opentubex https://github.com/OpenTubeX/scoop-bucket
scoop install opentubex/opentubex
```

Scoop adds OpenTubeX to the Start menu. Updates install with:

```powershell
scoop update opentubex
```

## Nightly builds

The `opentubex-nightly` package installs the daily development builds:

```powershell
scoop install opentubex/opentubex-nightly
```

Nightly builds are meant for testing and may be unstable. The package also
receives each stable release and then the nightlies that follow it. It appears
as **OpenTubeX Nightly** in the Start menu.

## Your data

Scoop installs OpenTubeX as a regular app, so it keeps its settings and data in
`%APPDATA%\OpenTubeX` like the Windows installer does. Updates and uninstalls
leave that folder in place.

The stable and nightly packages use the same folder. Install only one of them;
to switch, uninstall one and install the other.

## Uninstall OpenTubeX

```powershell
scoop uninstall opentubex  # or opentubex-nightly
```

Delete `%APPDATA%\OpenTubeX` as well to remove your OpenTubeX data.

## How publishing works

After an OpenTubeX stable or nightly release finishes uploading its assets,
the application repository sends an `opentubex-release` or
`opentubex-nightly` repository dispatch containing the release tag. The
**Update manifests** workflow then:

1. reads that release and validates its Windows portable ZIP assets and
   SHA-256 digests;
2. updates the version, URLs, and checksums in `bucket/opentubex.json` for
   stable releases and in `bucket/opentubex-nightly.json` for both stable and
   nightly releases. The nightly manifest keeps its version when the release is
   older than the build it already offers;
3. installs each changed manifest with Scoop on x64 and ARM64 runners, starts
   OpenTubeX, checks that it runs as an installed app, and uninstalls it;
4. publishes the tested manifests with GitHub-signed commits.

The workflow reuses the official release packages without rebuilding the app.
It can also be run manually. Without a tag, it picks up the latest stable
release:

```sh
gh workflow run update.yml --repo OpenTubeX/scoop-bucket --ref main
gh workflow run update.yml --repo OpenTubeX/scoop-bucket --ref main \
  -f releaseTag=v0.37.3-nightly-2677
```

## Maintainer setup

Enable GitHub Actions for this repository. The update workflow uses its
built-in `GITHUB_TOKEN` with `contents: write` permission to publish manifest
changes; no additional secret is needed here.

The OpenTubeX application repository uses its existing `PUSH_TOKEN` secret to
send the repository dispatches. That token needs Contents write access to
`OpenTubeX/scoop-bucket`.

The **Test manifests** workflow installs both manifests on x64 and ARM64
runners. Run the updater tests locally with:

```sh
python3 -m unittest discover -s tests
```
