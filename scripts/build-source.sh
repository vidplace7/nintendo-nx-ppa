#!/bin/bash
# Build an unsigned Debian source package from an upstream git branch.
#
# Usage: scripts/build-source.sh <package-dir> <dist> [out-dir]
#
#   <package-dir>  directory holding settings.sh and debian/<dist>/ (e.g. mesa)
#   <dist>         Ubuntu series (e.g. resolute)
#   [out-dir]      where the source package is written (default: build/<package-dir>/<dist>)
#
# Environment:
#   PPA              owner/name; if set, skip the build when the computed
#                    version is already in that PPA (any status)
#   INC              packaging revision; defaults to the number of commits in
#                    this repo touching <package-dir>, so packaging changes
#                    always produce a new version
#   DEBFULLNAME, DEBEMAIL   changelog signature
#   GITHUB_OUTPUT    if set, needed/version/changes are written to it
#
# Version: <upstream>{~|+}git<YYMMDDHHMM>.<hash10>~<d>~<PPA_SUFFIX><INC>
# where <d> is the first letter of the series, as in ernstp/ppa-mesarc.

set -euo pipefail

PKGDIR=${1:?package dir}
DIST=${2:?dist}
REPO=$(cd "$(dirname "$0")/.." && pwd)
PKGDIR=${PKGDIR%/}
OUT=${3:-$REPO/build/$PKGDIR/$DIST}

output() {
	echo "$1=$2"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "$1=$2" >> "$GITHUB_OUTPUT"
	fi
}

PREBUMP=
PPA_SUFFIX=ppa
source "$REPO/$PKGDIR/settings.sh"
PACKAGE_NAME=${PACKAGE_NAME:-$PKGDIR}
GITBRANCH=${GITBRANCH:-main}

if [ ! -d "$REPO/$PKGDIR/debian/$DIST" ]; then
	echo "No packaging for $DIST in $PKGDIR/debian/$DIST" >&2
	exit 1
fi

if [ -z "${INC:-}" ]; then
	if [ "$(git -C "$REPO" rev-parse --is-shallow-repository)" = true ]; then
		echo "Shallow checkout: INC can't be derived from history, set INC or fetch full history" >&2
		exit 1
	fi
	INC=$(git -C "$REPO" rev-list --count HEAD -- "$PKGDIR")
fi

WORK=$OUT/.work
UPSTREAM=$WORK/upstream
rm -rf "$OUT"
mkdir -p "$WORK"

echo "Cloning $GIT ($GITBRANCH)"
git clone --quiet --depth 50 --single-branch --branch "$GITBRANCH" "$GIT" "$UPSTREAM"

if [ -e "$UPSTREAM/VERSION" ]; then
	PACKAGE_VERSION=$(sed 's/-devel//' "$UPSTREAM/VERSION")
elif [ -e "$UPSTREAM/meson.build" ]; then
	PACKAGE_VERSION=$(grep -m 1 -E "^\s+version\s*:" "$UPSTREAM/meson.build" | grep -o -E '[0-9]+\.[0-9]+(\.[0-9]+)?') || true
fi
if [ -z "${PACKAGE_VERSION:-}" ]; then
	echo "Couldn't find upstream version" >&2
	exit 1
fi
# Change -rc1 to ~rc1
PACKAGE_VERSION=$(echo "$PACKAGE_VERSION" | sed 's/-rc/~rc/')

if [ -n "$PREBUMP" ]; then
	SEPARATOR="~"
else
	SEPARATOR="+"
fi

GIT_REV=$(git -C "$UPSTREAM" rev-parse HEAD)
GIT_DATE=$(TZ=UTC git -C "$UPSTREAM" show -s --date=format-local:%y%m%d%H%M --format=%cd HEAD)
VERSION=${PACKAGE_VERSION}${SEPARATOR}git${GIT_DATE}.${GIT_REV:0:10}~${DIST:0:1}~${PPA_SUFFIX}${INC}
output version "$VERSION"

if [ -n "${PPA:-}" ]; then
	found=$(curl -fsSL --retry 3 --get "https://api.launchpad.net/devel/~${PPA%%/*}/+archive/ubuntu/${PPA#*/}" \
		--data-urlencode ws.op=getPublishedSources \
		--data-urlencode source_name="$PACKAGE_NAME" \
		--data-urlencode version="$VERSION" \
		--data-urlencode exact_match=true | jq '.entries | length')
	if [ "$found" != 0 ]; then
		echo "$PACKAGE_NAME $VERSION is already in ppa:$PPA, nothing to do"
		output needed false
		exit 0
	fi
fi

SRC=$OUT/${PACKAGE_NAME}-${VERSION}
mkdir -p "$SRC"
git -C "$UPSTREAM" archive --format=tar HEAD | tar -x -C "$SRC"
cp -R "$REPO/$PKGDIR/debian/$DIST" "$SRC/debian"

(
	cd "$SRC"
	dch --create --package "$PACKAGE_NAME" --newversion "$VERSION" --distribution "$DIST" --force-distribution \
		"Snapshot of $GIT $GITBRANCH at ${GIT_REV:0:12}"
	git -C "$UPSTREAM" log -n 30 --format='%h %s' HEAD | while read -r change; do
		dch -a -- "$change"
	done
	# dpkg-buildpackage reads debian/control before the clean target regenerates it
	debian/rules regen_control
	dpkg-buildpackage -S -d -us -uc
)

rm -rf "$WORK" "$SRC"
CHANGES=$OUT/${PACKAGE_NAME}_${VERSION}_source.changes
if [ ! -e "$CHANGES" ]; then
	echo "Missing $CHANGES" >&2
	exit 1
fi
output needed true
output changes "$CHANGES"
