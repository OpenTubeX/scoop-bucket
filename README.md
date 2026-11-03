# OpenTubeX Scoop bucket

This repository distributes [OpenTubeX](https://github.com/OpenTubeX/OpenTubeX)
through [Scoop](https://scoop.sh/) on Windows. It supports x64 and ARM64.

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

Both packages use the portable OpenTubeX build. Scoop keeps its data in
`persist\opentubex\OpenTubeX-data` or `persist\opentubex-nightly\OpenTubeX-data`
inside your Scoop directory, so updates keep your settings. The stable and
nightly packages have separate data and can be installed side by side. To move
your data between them, use **Export backup** in one and **Import backup** in
the other, under **Settings → Data & Storage**.

## Uninstall OpenTubeX

```powershell
scoop uninstall opentubex  # or opentubex-nightly
```

Add `--purge` to delete your OpenTubeX data as well.

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
   OpenTubeX, checks that its data lands in the persisted directory, and
   uninstalls it;
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
