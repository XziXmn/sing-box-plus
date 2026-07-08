_sysctl() {
	local sysctl_bin
	for sysctl_bin in "$(type -P sysctl)" /usr/sbin/sysctl /sbin/sysctl /bin/sysctl; do
		[[ -x "$sysctl_bin" ]] && "$sysctl_bin" "$@" && return
	done
	return 1
}

_modprobe_tcp_bbr() {
	local modprobe_bin
	for modprobe_bin in "$(type -P modprobe)" /usr/sbin/modprobe /sbin/modprobe /bin/modprobe; do
		[[ -x "$modprobe_bin" ]] && "$modprobe_bin" tcp_bbr 2>/dev/null && return
	done
	return 1
}

_modinfo_tcp_bbr() {
	local modinfo_bin
	for modinfo_bin in "$(type -P modinfo)" /usr/sbin/modinfo /sbin/modinfo /bin/modinfo; do
		[[ -x "$modinfo_bin" ]] && "$modinfo_bin" tcp_bbr 2>/dev/null && return
	done
	return 1
}

_bbr_read_sysctl() {
	local bbr_key=$1
	local bbr_proc="/proc/sys/${bbr_key//./\/}"
	if [[ -r "$bbr_proc" ]]; then
		cat "$bbr_proc"
	else
		_sysctl -n "$bbr_key" 2>/dev/null
	fi
}

_bbr_write_sysctl() {
	local bbr_key=$1
	local bbr_value=$2
	local bbr_proc="/proc/sys/${bbr_key//./\/}"
	if _sysctl -w "$bbr_key=$bbr_value" >/dev/null 2>&1; then
		return
	fi
	[[ -w "$bbr_proc" ]] && echo "$bbr_value" >"$bbr_proc"
}

_open_bbr() {
	local bbr_conf=/etc/sysctl.d/99-sing-box-plus-bbr.conf

	mkdir -p /etc/sysctl.d || {
		bbr_error="创建 /etc/sysctl.d 失败"
		return 1
	}
	touch "$bbr_conf" || {
		bbr_error="无法写入 $bbr_conf"
		return 1
	}
	if ! _bbr_available; then
		bbr_error="当前系统未提供 bbr 拥塞控制算法"
		return 1
	fi
	sed -i \
		-e '/^net\.ipv4\.tcp_congestion_control[[:space:]]*=/d' \
		-e '/^net\.core\.default_qdisc[[:space:]]*=/d' \
		"$bbr_conf" || {
		bbr_error="更新 $bbr_conf 失败"
		return 1
	}
	{
		echo "net.ipv4.tcp_congestion_control = bbr"
		echo "net.core.default_qdisc = fq"
	} >>"$bbr_conf" || {
		bbr_error="写入 $bbr_conf 失败"
		return 1
	}
	_bbr_write_sysctl net.ipv4.tcp_congestion_control bbr || {
		bbr_error="应用 tcp_congestion_control 失败"
		return 1
	}
	_bbr_write_sysctl net.core.default_qdisc fq || {
		bbr_error="应用 default_qdisc 失败"
		return 1
	}
	_sysctl --system &>/dev/null || true
	[[ $(_bbr_read_sysctl net.ipv4.tcp_congestion_control 2>/dev/null) == "bbr" ]] || {
		bbr_error="系统未切换到 bbr"
		return 1
	}
	echo
	_green "..已经启用 BBR 优化...."
	echo
}

_kernel_supports_bbr() {
	local _test1=$(uname -r | cut -d\. -f1)
	local _test2=$(uname -r | cut -d\. -f2)
	[[ $_test1 -eq 4 && $_test2 -ge 9 ]] || [[ $_test1 -ge 5 ]]
}

_bbr_available() {
	local bbr_available bbr_current
	bbr_current=$(_bbr_read_sysctl net.ipv4.tcp_congestion_control 2>/dev/null)
	[[ "$bbr_current" == "bbr" ]] && return 0

	bbr_available=$(_bbr_read_sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null)
	[[ " $bbr_available " == *" bbr "* ]] && return 0

	_modprobe_tcp_bbr || true
	bbr_available=$(_bbr_read_sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null)
	[[ " $bbr_available " == *" bbr "* ]]
}

_try_enable_bbr() {
	if ! _bbr_available && ! _kernel_supports_bbr; then
		err "不支持启用 BBR 优化."
	fi
	_bbr_available || err "启用 BBR 优化失败: 当前系统未提供 bbr 拥塞控制算法"
	_open_bbr || err "启用 BBR 优化失败: ${bbr_error:-未知原因}"
}

_bbr_version_label() {
	local bbr_module bbr_current bbr_available bbr_kernel
	bbr_module=$(_modinfo_tcp_bbr | awk '/^version:/ {print $2; exit}')
	bbr_kernel=$(uname -r | tr '[:upper:]' '[:lower:]')
	if [[ "$bbr_module" == 3* || "$bbr_kernel" == *bbrv3* || "$bbr_kernel" == *bbr3* ]]; then
		echo "BBRv3"
		return
	fi
	if [[ "$bbr_module" == 2* || "$bbr_kernel" == *bbrv2* || "$bbr_kernel" == *bbr2* || "$bbr_kernel" == *v2alpha* ]]; then
		echo "BBRv2"
		return
	fi
	if [[ "$bbr_module" == 1* ]]; then
		echo "BBRv1"
		return
	fi
	bbr_current=$(_bbr_read_sysctl net.ipv4.tcp_congestion_control 2>/dev/null)
	bbr_available=$(_bbr_read_sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null)
	if [[ "$bbr_current" == "bbr" || " $bbr_available " == *" bbr "* ]]; then
		echo "BBRv1"
	else
		echo "未知"
	fi
}

_bbr_show_status() {
	local bbr_current bbr_available qdisc bbr_module
	bbr_current=$(_bbr_read_sysctl net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
	bbr_available=$(_bbr_read_sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)
	qdisc=$(_bbr_read_sysctl net.core.default_qdisc 2>/dev/null || echo unknown)
	bbr_module=$(_modinfo_tcp_bbr | awk '/^version:/ {print $2; exit}')

	msg "\n当前内核: $(uname -r)"
	msg "当前拥塞控制: $bbr_current"
	msg "可用拥塞控制: $bbr_available"
	msg "默认队列算法: $qdisc"
	msg "BBR 类型: $(_bbr_version_label)"
	msg "tcp_bbr 模块版本: ${bbr_module:-未知或未提供 version}"
}

_bbrv3_prepare_sudo() {
	type -P sudo &>/dev/null && return
	[[ $(id -u) -eq 0 ]] || err "缺少 sudo，请使用 root 用户执行."
	sudo() { "$@"; }
	export -f sudo
}

_bbrv3_run() {
	local bbrv3_input=$1
	local bbrv3_url="https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/main/install.sh"
	local bbrv3_script="/tmp/sing-box-plus-bbrv3.sh"

	if [[ ! -s "$bbrv3_script" ]]; then
		msg "\n未检测到 BBRv3 脚本，开始下载 > $bbrv3_url"
		_wget -t 3 -q -O "$bbrv3_script" "$bbrv3_url" || err "下载 BBRv3 脚本失败."
	else
		msg "\n检测到 BBRv3 脚本 > $bbrv3_script"
	fi
	[[ -s "$bbrv3_script" ]] || err "BBRv3 脚本不存在或为空."
	chmod +x "$bbrv3_script"
	_bbrv3_prepare_sudo
	if [[ $bbrv3_input ]]; then
		printf "%b" "$bbrv3_input" | bash "$bbrv3_script"
	else
		bash "$bbrv3_script"
	fi
}

_bbrv3_install_standard() {
	warn "将运行 BBRv3 脚本安装/更新 BBRv3 标准内核，完成后通常需要重启系统."
	ask string y "确认继续? 输入 y:"
	_bbrv3_run "1\n\n"
}

_bbrv3_apac_tuning() {
	warn "将调用 BBRv3 脚本执行亚太机器 TCP 调优."
	ask string y "确认继续? 输入 y:"
	_bbrv3_run "8\n"
}

_bbr_menu() {
	is_tmp_list=("启用系统自带 BBR" "查看 BBR 状态" "安装/更新 BBRv3 标准内核" "运行 BBRv3 脚本" "亚太机器 TCP 调优")
	ask list is_do_bbr null "\n请选择 BBR 设置:\n"
	case $REPLY in
	1)
		_try_enable_bbr
		;;
	2)
		_bbr_show_status
		;;
	3)
		_bbrv3_install_standard
		;;
	4)
		_bbrv3_run
		;;
	5)
		_bbrv3_apac_tuning
		;;
	esac
}

_bbr_status() {
	bbr_current=$(_bbr_read_sysctl net.ipv4.tcp_congestion_control 2>/dev/null)
	if [[ "$bbr_current" == "bbr" ]]; then
		is_bbr_enabled=1
		is_bbr_available=1
		is_bbr_status=$(_green "已启用 ($(_bbr_version_label))")
	elif _bbr_available; then
		is_bbr_enabled=
		is_bbr_available=1
		is_bbr_status=$(_red_bg "未启用")
	else
		is_bbr_enabled=
		is_bbr_available=
		is_bbr_status=$(_red_bg "不可用")
	fi
}

_prompt_enable_bbr() {
	_bbr_status
	[[ $is_bbr_enabled ]] && return
	[[ $is_bbr_available ]] || return

	echo -ne "检测到 BBR 未启用，是否立即启用? [y/N]:"
	read -r is_enable_bbr
	[[ $(grep -i ^y$ <<<"$is_enable_bbr") ]] && _try_enable_bbr
	_bbr_status
}

_auto_enable_bbr() {
	local _current_bbr
	_current_bbr=$(_bbr_read_sysctl net.ipv4.tcp_congestion_control 2>/dev/null)
	[[ "$_current_bbr" == "bbr" ]] && return

	local _virt
	_virt=$(systemd-detect-virt 2>/dev/null || true)
	[[ "$_virt" =~ lxc|openvz ]] && return

	_bbr_available || return

	_open_bbr &>/dev/null || true
}
