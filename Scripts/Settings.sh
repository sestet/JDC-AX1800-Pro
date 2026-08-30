#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
	if [[ "${WRT_WIFI_OPEN:-false}" == "true" ]]; then
		# ImmortalWrt official first-boot Wi-Fi defaults: enabled and open.
		sed -i "s/encryption='.*'/encryption='none'/g" $WIFI_UC
		sed -i "s/key='.*'/key=''/g" $WIFI_UC
		sed -i "s/disabled='.*'/disabled='0'/g" $WIFI_UC
	else
		#修改WIFI密码和加密
		sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
		sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
	fi
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config
#APK插件切换回IPK
echo "CONFIG_USE_APK=n" >> ./.config

# Arthur's eMMC is worn, so keep nlbwmon's frequently updated database in RAM.
if [[ "${WRT_PACKAGE_PROFILE:-general}" == "arthur" ]]; then
	CLOUDFLARED_MENU=$(find ./feeds/luci/applications/luci-app-cloudflared/ -type f -name 'luci-app-cloudflared.json' -print -quit 2>/dev/null)
	[ -n "$CLOUDFLARED_MENU" ] || {
		echo "luci-app-cloudflared menu definition was not found" >&2
		exit 1
	}
	sed -i 's#admin/vpn/cloudflared#admin/services/cloudflared#g' "$CLOUDFLARED_MENU"
	if grep -qF 'admin/vpn/cloudflared' "$CLOUDFLARED_MENU" || \
		! grep -qF 'admin/services/cloudflared' "$CLOUDFLARED_MENU"; then
		echo "Failed to move Cloudflare Tunnel to the Services menu" >&2
		exit 1
	fi

	UHTTPD_CONFIG="./package/network/services/uhttpd/files/uhttpd.config"
	[ -f "$UHTTPD_CONFIG" ] || {
		echo "uhttpd.config was not found" >&2
		exit 1
	}
	sed -i -E \
		-e 's|^[[:space:]]*#[[:space:]]*list listen_https[[:space:]]+0\.0\.0\.0:443|	list listen_https	0.0.0.0:443|' \
		-e 's|^[[:space:]]*#[[:space:]]*list listen_https[[:space:]]+\[::\]:443|	list listen_https	[::]:443|' \
		-e "s|^[[:space:]]*option redirect_https[[:space:]]+.*|	option redirect_https	0|" \
		"$UHTTPD_CONFIG"
	if ! grep -Eq '^[[:space:]]*list listen_https[[:space:]]+0\.0\.0\.0:443$' "$UHTTPD_CONFIG" || \
		! grep -Eq '^[[:space:]]*list listen_https[[:space:]]+\[::\]:443$' "$UHTTPD_CONFIG" || \
		! grep -Eq '^[[:space:]]*option redirect_https[[:space:]]+0$' "$UHTTPD_CONFIG"; then
		echo "Failed to configure simultaneous HTTP and HTTPS access" >&2
		exit 1
	fi

	NLBWMON_CONFIG=$(find ./feeds/packages/net/nlbwmon/ -type f -name "nlbwmon.config" -print -quit 2>/dev/null)
	if [ -z "$NLBWMON_CONFIG" ]; then
		echo "nlbwmon.config was not found" >&2
		exit 1
	fi
	sed -i 's#option database_directory .*#option database_directory /tmp/nlbwmon#' "$NLBWMON_CONFIG"
	grep -qF 'option database_directory /tmp/nlbwmon' "$NLBWMON_CONFIG" || {
		echo "Failed to move the nlbwmon database to RAM" >&2
		exit 1
	}

	FWTOOL_SH="./package/base-files/files/lib/upgrade/fwtool.sh"
	FWTOOL_PATCH="$GITHUB_WORKSPACE/Patches/001-fix-fwtool-compat-check.patch"
	FWTOOL_BROKEN='if (([ "${devicecompat#.*}" != "${imagecompat#.*}" ] || [ "$dev" = "$oem" ])) && [ "$SAVE_CONFIG" = "1" ]; then'
	FWTOOL_FIXED='if { [ "${devicecompat#.*}" != "${imagecompat#.*}" ] || [ "$dev" = "$oem" ]; } && [ "$SAVE_CONFIG" = "1" ]; then'

	if grep -qF "$FWTOOL_BROKEN" "$FWTOOL_SH"; then
		patch -p1 --forward < "$FWTOOL_PATCH"
	fi
	grep -qF "$FWTOOL_FIXED" "$FWTOOL_SH" || {
		echo "Failed to apply the fwtool compatibility-check fix" >&2
		exit 1
	}
fi

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#无WIFI配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi
