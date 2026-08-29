#!/bin/bash
# SPDX-License-Identifier: MIT

set -euo pipefail

AURORA_COMMIT="2fbd1241741c2e760f9665aa3f39a9cf7e14123b"
AURORA_CONFIG_COMMIT="110aeca1ffab6d2dece43dcd28b15efe00d5ca83"
OPENCLASH_COMMIT="5f270df6ca97f02c5476849f1b2724b64b7eef01"
OPENCLASH_CORE_COMMIT="6625f341886253db3e44f9ded0cc1cd6b8bcbc3d"
OPENCLASH_CORE_SHA256="8252d16726041872825cdd9089c798c318f8862466b40b34d8bf62225ef57e34"
ISTORE_COMMIT="3fca15b30aeed9ecacb3efc8b4a8b9c2584ad5c7"

checkout_repo() {
	local repository="$1"
	local commit="$2"
	local destination="$3"

	git init -q "$destination"
	git -C "$destination" remote add origin "https://github.com/$repository.git"
	git -C "$destination" fetch -q --depth=1 origin "$commit"
	git -C "$destination" checkout -q --detach FETCH_HEAD
	rm -rf "$destination/.git"
}

verify_sha256() {
	local expected="$1"
	local file="$2"

	if command -v sha256sum >/dev/null 2>&1; then
		echo "$expected  $file" | sha256sum -c -
	elif command -v shasum >/dev/null 2>&1; then
		local actual
		actual="$(shasum -a 256 "$file" | awk '{print $1}')"
		[ "$actual" = "$expected" ] || {
			echo "SHA-256 mismatch for $file" >&2
			return 1
		}
	else
		echo "No SHA-256 checker is available" >&2
		return 1
	fi
}

echo "Installing pinned Arthur package sources"

checkout_repo "eamonxg/luci-theme-aurora" "$AURORA_COMMIT" "luci-theme-aurora"
checkout_repo "eamonxg/luci-app-aurora-config" "$AURORA_CONFIG_COMMIT" "luci-app-aurora-config"

OPENCLASH_SOURCE="$(mktemp -d)"
ISTORE_SOURCE="$(mktemp -d)"
trap 'rm -rf "$OPENCLASH_SOURCE" "$ISTORE_SOURCE"' EXIT INT TERM

checkout_repo "vernesong/OpenClash" "$OPENCLASH_COMMIT" "$OPENCLASH_SOURCE"
cp -a "$OPENCLASH_SOURCE/luci-app-openclash" ./

CORE_ARCHIVE="$(mktemp)"
curl -fsSL --retry 3 --retry-all-errors \
	"https://raw.githubusercontent.com/vernesong/OpenClash/$OPENCLASH_CORE_COMMIT/master/meta/clash-linux-arm64.tar.gz" \
	-o "$CORE_ARCHIVE"
verify_sha256 "$OPENCLASH_CORE_SHA256" "$CORE_ARCHIVE"
mkdir -p luci-app-openclash/root/etc/openclash/core
tar -xzf "$CORE_ARCHIVE" -C luci-app-openclash/root/etc/openclash/core
mv luci-app-openclash/root/etc/openclash/core/clash \
	luci-app-openclash/root/etc/openclash/core/clash_meta
chmod 0755 luci-app-openclash/root/etc/openclash/core/clash_meta
rm -f "$CORE_ARCHIVE"

checkout_repo "linkease/istore" "$ISTORE_COMMIT" "$ISTORE_SOURCE"
for package in luci-app-store luci-lib-taskd luci-lib-xterm taskd; do
	cp -a "$ISTORE_SOURCE/luci/$package" ./
done

rm -rf "$OPENCLASH_SOURCE" "$ISTORE_SOURCE"
trap - EXIT INT TERM

echo "Arthur package sources installed"
