# nintendo-nx-ppa

Ubuntu packaging for Nintendo Switch (Tegra X1) packages, published to
[ppa:vidplace7/nintendo-nx](https://launchpad.net/~vidplace7/+archive/ubuntu/nintendo-nx).

| Package | Upstream | Series |
|---------|----------|--------|
| `mesa`  | [mojyack/mesa `t210-develop`](https://gitlab.freedesktop.org/mojyack/mesa/-/tree/t210-develop) | resolute (26.04) |

The packaging layout follows [ernstp/ppa-mesarc](https://github.com/ernstp/ppa-mesarc):
`<package>/settings.sh` names the upstream branch and `<package>/debian/<series>/`
holds the packaging for each Ubuntu series. Mesa's packaging is based on
ppa-mesarc's `mesa-aco` (which also tracks Mesa main) with NVK and Rust
enabled on arm64.

## How it works

`.github/workflows/mesa.yml` runs daily, on pushes to `main` that touch the
packaging, and on demand:

1. **source**: `scripts/build-source.sh` clones the upstream branch, computes the
   version, and asks Launchpad whether that version is already in the PPA. If it
   isn't, it builds an unsigned source package (`dpkg-buildpackage -S`).
   Pull requests and manual runs with **upload** enabled bypass this version check.
2. **test-build**: builds the binary packages in an `ubuntu:resolute` container on
   a GitHub arm64 runner, so a broken snapshot never reaches the Launchpad queue.
   It can be skipped from the manual run form.
3. **upload**: signs the `.changes` with the PPA signing key and `dput`s it.
   Only runs on `main`, never for pull requests.
   Manual runs with **upload** enabled attempt the upload even if the version
   already exists; Launchpad may reject an upload of an existing version.

Versions look like `27.0.0~git2610251245.e737139f66~r~nx12`:

- `27.0.0~` upstream `VERSION` (already bumped, so `~` sorts below the release)
- `git2610251245.e737139f66` upstream commit time (UTC) and hash
- `r` the series' first letter
- `nx12` the number of commits in this repo touching `mesa/`

So a new upstream commit or any packaging commit produces a new version, and
an unchanged pair is skipped. To force a no-change rebuild, commit something
under `mesa/` (for example a note in `debian/<series>/README.source`).

## CI configuration

| Kind | Name | Value |
|------|------|-------|
| secret | `PPA_GPG_PRIVATE_KEY` | armored private key (no passphrase) registered on Launchpad |
| variable | `PPA_GPG_KEY_ID` | its fingerprint (optional; defaults to the first secret key) |
| variable | `DEBFULLNAME`, `DEBEMAIL` | changelog signature (optional) |

## Building locally

On Ubuntu with `devscripts debhelper quilt jq git` installed:

```bash
scripts/build-source.sh mesa resolute
```

The source package lands in `build/mesa/resolute/`. Sign and upload by hand with:

```bash
debsign build/mesa/resolute/*_source.changes && dput ppa:vidplace7/nintendo-nx build/mesa/resolute/*_source.changes
```

## Using the PPA

```bash
sudo add-apt-repository ppa:vidplace7/nintendo-nx
```

If Ubuntu later ships a Mesa release in `resolute-updates` that sorts above
the snapshot here, pin the PPA in `/etc/apt/preferences.d/`.

## Why not Launchpad source recipes?

Recipes could technically do this: Launchpad would need a code import of the
fork and a Launchpad-hosted copy of this packaging, and a recipe would merge
them daily. In practice they are a poor fit:

- Code imports of a Mesa-sized fork are slow to create and refresh, and
  recipes only build at most once a day after the import catches up.
- The packaging would have to live in, or be mirrored to, Launchpad git.
- No hook to run anything before the build: the changelog is a generic entry,
  `debian/control` has to be committed pre-generated, and the version can only
  use the fixed recipe variables.
- Nothing builds the binaries before they hit the PPA queue, and failures
  only show up in Launchpad build logs.

GitHub Actions keeps the packaging here, controls the version, test-builds on
arm64 first, and uploads a signed source package straight to the PPA.
