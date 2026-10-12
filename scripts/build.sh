#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${RUNNER_TEMP:-/tmp}/openwrt-19.07.9"
SRC_DIR="${WORK_DIR}/source"
OUT_DIR="${ROOT_DIR}/output"
EXPECTED_KERNEL_ABI="${EXPECTED_KERNEL_ABI:-4.14.267-1-b84a5a29b1d5ae1dc33ccf9ba292ca1d}"
OPENWRT_TAG="${OPENWRT_TAG:-v19.07.9}"
DEVICE_PROFILE="${DEVICE_PROFILE:-tplink_tl-wr841hp-v3}"
MAX_IMAGE_KIB="${MAX_IMAGE_KIB:-7808}"

fail() { echo "::error::$*" >&2; exit 1; }

rm -rf "${WORK_DIR}" "${OUT_DIR}"
mkdir -p "${WORK_DIR}" "${OUT_DIR}"

echo "== Clone OpenWrt ${OPENWRT_TAG}"
git clone --depth 1 --branch "${OPENWRT_TAG}" https://git.openwrt.org/openwrt/openwrt.git "${SRC_DIR}"
cd "${SRC_DIR}"

echo "== Apply backport patches"
shopt -s nullglob
patches=("${ROOT_DIR}"/patches/*.patch)
if (("${#patches[@]}" == 0)); then
  fail "WR841HP v3 backport patch missing in patches/*.patch. Build stopped to avoid creating an unsupported image."
fi
for p in "${patches[@]}"; do
  echo "-- Applying $(basename "$p")"
  patch -p1 --forward --batch < "$p" || fail "Patch failed: $p"
done

echo "== Verify device profile exists"
grep -Rqs --include='*.mk' --include='*.in' "${DEVICE_PROFILE}" target/linux/ath79 ||
  fail "Profile ${DEVICE_PROFILE} not found after patch. DTS and image recipe are required."

echo "== Update/install feeds"
./scripts/feeds update -a
./scripts/feeds install -a

echo "== Configure target"
make defconfig

cat >> .config <<'CONFIG_EOF'
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_PROFILE="DEVICE_tplink_tl-wr841hp-v3"

# Minimal LuCI
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-mod-admin-full=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_uhttpd=y
CONFIG_PACKAGE_uhttpd-mod-ubus=y

# Wi-Fi and essential network services
CONFIG_PACKAGE_kmod-ath9k=y
CONFIG_PACKAGE_wpad-mini=y
CONFIG_PACKAGE_dnsmasq=y
CONFIG_PACKAGE_dropbear=y
CONFIG_PACKAGE_firewall=y
CONFIG_PACKAGE_netifd=y
CONFIG_PACKAGE_logd=y
CONFIG_PACKAGE_opkg=y
CONFIG_PACKAGE_procd=y
CONFIG_PACKAGE_uci=y

# Install openNDS; disable its init service in first-boot defaults
CONFIG_PACKAGE_opennds=y

# Remove IPv6 userland and PPP/PPPoE packages.
# Do not force kernel IPv6 Kconfig off: kernel ABI compatibility is checked below.
CONFIG_PACKAGE_odhcp6c=n
CONFIG_PACKAGE_odhcpd=n
CONFIG_PACKAGE_odhcpd-ipv6only=n
CONFIG_PACKAGE_ip6tables=n
CONFIG_PACKAGE_ppp=n
CONFIG_PACKAGE_ppp-mod-pppoe=n
CONFIG_PACKAGE_ppp-mod-pptp=n
CONFIG_PACKAGE_kmod-pppoe=n
CONFIG_PACKAGE_kmod-pppox=n
CONFIG_PACKAGE_kmod-slhc=n
CONFIG_PACKAGE_luci-proto-ipv6=n
CONFIG_PACKAGE_luci-proto-ppp=n
CONFIG_EOF

make defconfig

grep -q '^CONFIG_PACKAGE_opennds=y' .config || fail "opennds is unavailable or not selected."
grep -q '^CONFIG_PACKAGE_wpad-mini=y' .config || fail "wpad-mini is not selected."
grep -q '^CONFIG_TARGET_ath79_generic=y' .config || fail "ath79/generic target not selected."

mkdir -p files/etc/uci-defaults
cp "${ROOT_DIR}"/files/etc/uci-defaults/* files/etc/uci-defaults/

echo "== Compile"
make -j"$(nproc)" V=s

echo "== Verify kernel ABI"
KERNEL_META="$(find bin -type f -name 'kernel_*.ipk' | head -n1 || true)"
if [[ -z "${KERNEL_META}" ]]; then
  KERNEL_VERSION="$(grep -RhoE 'Version: 4\.14\.267-[^[:space:]]+' bin/targets bin/packages 2>/dev/null | head -n1 | sed 's/^Version: //')"
else
  KERNEL_VERSION="$(basename "${KERNEL_META}" | sed -E 's/^kernel_([^_]+)_.*/\1/')"
fi
printf 'Expected kernel ABI: %s\nDetected kernel package version: %s\n' \
  "${EXPECTED_KERNEL_ABI}" "${KERNEL_VERSION:-NOT_FOUND}" | tee "${ROOT_DIR}/build-metadata.txt"
[[ "${KERNEL_VERSION:-}" == "${EXPECTED_KERNEL_ABI}" ]] ||
  fail "Kernel ABI mismatch. Expected ${EXPECTED_KERNEL_ABI}; got ${KERNEL_VERSION:-NOT_FOUND}."

echo "== Collect factory/sysupgrade images"
mapfile -t images < <(find bin/targets/ath79/generic -type f \( -name '*factory*.bin' -o -name '*sysupgrade*.bin' \))
(("${#images[@]}" > 0)) || fail "No factory/sysupgrade images found."
for img in "${images[@]}"; do
  size_kib=$(( ($(stat -c%s "$img") + 1023) / 1024 ))
  echo "$(basename "$img"): ${size_kib} KiB"
  (( size_kib <= MAX_IMAGE_KIB )) || fail "$(basename "$img") exceeds ${MAX_IMAGE_KIB} KiB."
  cp "$img" "${OUT_DIR}/"
done
cp .config "${OUT_DIR}/.config"
cp "${ROOT_DIR}/build-metadata.txt" "${OUT_DIR}/"
echo "Build complete. Test boot, Wi-Fi, LAN and sysupgrade on hardware before use."
