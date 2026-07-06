_open_bbr() {
	[[ -w /etc/sysctl.conf ]] || {
		bbr_error="无法写入 /etc/sysctl.conf"
		return 1
	}
	modprobe tcp_bbr 2>/dev/null || true
	if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
		bbr_error="当前系统未提供 tcp_bbr 模块"
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

_try_enable_bbr() {
	if _kernel_supports_bbr; then
		_open_bbr || err "启用 BBR 优化失败: ${bbr_error:-未知原因}"
	else
		err "不支持启用 BBR 优化."
	fi
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
