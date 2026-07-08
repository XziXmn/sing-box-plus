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
	sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null || {
		bbr_error="应用 tcp_congestion_control 失败"
		return 1
	}
	sysctl -w net.core.default_qdisc=fq >/dev/null || {
		bbr_error="应用 default_qdisc 失败"
		return 1
	}
	sysctl --system &>/dev/null || {
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
	local bbr_available bbr_current
	bbr_current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
	[[ "$bbr_current" == "bbr" ]] && return 0

	bbr_available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
	[[ " $bbr_available " == *" bbr "* ]] && return 0

	type -P modprobe &>/dev/null && modprobe tcp_bbr 2>/dev/null || true
	bbr_available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)
	[[ " $bbr_available " == *" bbr "* ]]
}

_try_enable_bbr() {
	if ! _bbr_available && ! _kernel_supports_bbr; then
		err "不支持启用 BBR 优化."
	fi
	_bbr_available || err "启用 BBR 优化失败: 当前系统未提供 bbr 拥塞控制算法"
	_open_bbr || err "启用 BBR 优化失败: ${bbr_error:-未知原因}"
}

_bbr_show_status() {
	local bbr_current bbr_available qdisc bbr_module
	bbr_current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
	bbr_available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo unknown)
	qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)
	bbr_module=$(modinfo tcp_bbr 2>/dev/null | awk '/^version:/ {print $2}')

	msg "\n当前内核: $(uname -r)"
	msg "当前拥塞控制: $bbr_current"
	msg "可用拥塞控制: $bbr_available"
	msg "默认队列算法: $qdisc"
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
		msg "\n未检测到 BBRv3 官方脚本，开始下载 > $bbrv3_url"
		_wget -t 3 -q -O "$bbrv3_script" "$bbrv3_url" || err "下载 BBRv3 官方脚本失败."
	else
		msg "\n检测到 BBRv3 官方脚本 > $bbrv3_script"
	fi
	[[ -s "$bbrv3_script" ]] || err "BBRv3 官方脚本不存在或为空."
	chmod +x "$bbrv3_script"
	_bbrv3_prepare_sudo
	if [[ $bbrv3_input ]]; then
		printf "%b" "$bbrv3_input" | bash "$bbrv3_script"
	else
		bash "$bbrv3_script"
	fi
}

_bbrv3_install_standard() {
	warn "将运行 byJoey 官方脚本安装/更新 BBRv3 标准内核，完成后通常需要重启系统."
	ask string y "确认继续? 输入 y:"
	_bbrv3_run "1\n\n"
}

_bbrv3_apac_tuning() {
	warn "将调用 byJoey 官方脚本执行亚太机器 TCP 调优."
	ask string y "确认继续? 输入 y:"
	_bbrv3_run "8\n"
}

_bbr_menu() {
	is_tmp_list=("启用系统自带 BBR" "查看 BBR 状态" "安装/更新 BBRv3 标准内核" "运行 BBRv3 官方脚本" "亚太机器 TCP 调优")
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
	bbr_current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
	if [[ "$bbr_current" == "bbr" ]]; then
		is_bbr_enabled=1
		is_bbr_available=1
		is_bbr_status=$(_green enabled)
	elif _bbr_available; then
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

	_bbr_available || return

	_open_bbr &>/dev/null || true
}
