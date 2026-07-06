_open_bbr() {
	[[ -w /etc/sysctl.conf ]] || return 1
	sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf || return 1
	sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf || return 1
	echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
	echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
	sysctl -p &>/dev/null || return 1
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
		_open_bbr || err "启用 BBR 优化失败."
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
	[[ "$_virt" =~ lxc|openvz ]] && {
		warn "当前虚拟化环境为 $_virt，跳过自动启用原版 BBR."
		return
	}

	_kernel_supports_bbr || {
		warn "当前内核不支持自动启用 BBR，已跳过."
		return
	}

	_open_bbr || warn "自动启用 BBR 失败，请稍后手动执行: $is_core bbr"
}
