_open_bbr() {
	[[ -w /etc/sysctl.conf ]] || {
		bbr_error="无法写入 /etc/sysctl.conf"
		return 1
	}
	if ! _bbr_available; then
		bbr_error="当前系统未提供 bbr 拥塞控制算法"
		return 1
	fi
	sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf || {
		bbr_error="更新 /etc/sysctl.conf 失败"
		return 1
	}
	sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf || {
		bbr_error="更新 /etc/sysctl.conf 失败"
		return 1
	}
	echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
	echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
	sysctl -p &>/dev/null || {
		bbr_error="应用 sysctl 配置失败"
		return 1
	}
	[[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) == "bbr" ]] || {
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
	modprobe tcp_bbr 2>/dev/null || true
	sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr
}

_try_enable_bbr() {
	if ! _kernel_supports_bbr; then
		err "不支持启用 BBR 优化."
	fi
	_bbr_available || err "启用 BBR 优化失败: 当前系统未提供 bbr 拥塞控制算法"
	_open_bbr || err "启用 BBR 优化失败: ${bbr_error:-未知原因}"
}

_bbr_status() {
	bbr_current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
	if [[ "$bbr_current" == "bbr" ]]; then
		is_bbr_enabled=1
		is_bbr_available=1
		is_bbr_status=$(_green enabled)
	elif _kernel_supports_bbr && _bbr_available; then
		is_bbr_enabled=
		is_bbr_available=1
		is_bbr_status=$(_red_bg disabled)
	else
		is_bbr_enabled=
		is_bbr_available=
		is_bbr_status=$(_red_bg unavailable)
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
	_current_bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
	[[ "$_current_bbr" == "bbr" ]] && return

	local _virt
	_virt=$(systemd-detect-virt 2>/dev/null || true)
	[[ "$_virt" =~ lxc|openvz ]] && return

	_kernel_supports_bbr || return

	_open_bbr &>/dev/null || true
}
