relay_config_prefix=relay-chain-
relay_parser_bin="$is_core_dir/bin/relay-parser"

relay_menu() {
    msg
    section_title "链式转发"
    msg "1. 添加配置"
    msg "2. 更改配置"
    msg "3. 删除配置"
    msg "0. 退出"
    ask string relay_choice "请选择:"

    case "$relay_choice" in
    1)
        relay_add_chain_menu
        ;;
    2)
        relay_change_chain_config
        ;;
    3)
        relay_delete_chain_config
        ;;
    0 | q | Q)
        exit
        ;;
    *)
        err "无效选择."
        ;;
    esac
}

relay_show_configs() {
    msg
    section_title "当前链式转发配置"
    if ! ls "$is_conf_dir"/${relay_config_prefix}*.json >/dev/null 2>&1; then
        msg "暂无链式转发配置."
        line_sep
        return
    fi

    for relay_file in "$is_conf_dir"/${relay_config_prefix}*.json; do
        relay_name=$(basename "$relay_file")
        relay_type=$(jq -r '.inbounds[0].type // "unknown"' "$relay_file" 2>/dev/null)
        relay_port=$(jq -r '.inbounds[0].listen_port // "unknown"' "$relay_file" 2>/dev/null)
        relay_host=$(jq -r '.inbounds[0].transport.headers.host // empty' "$relay_file" 2>/dev/null)
        relay_target_type=$(jq -r '.outbounds[0].type // "unknown"' "$relay_file" 2>/dev/null)
        relay_target=$(jq -r '.outbounds[0].server // "unknown"' "$relay_file" 2>/dev/null)
        relay_target_port=$(jq -r '.outbounds[0].server_port // "unknown"' "$relay_file" 2>/dev/null)
        if [[ $relay_host ]]; then
            msg "$relay_name | 入站:$relay_type:$relay_host:$is_https_port -> 后端:127.0.0.1:$relay_port -> 出站:$relay_target_type:$relay_target:$relay_target_port"
        else
            msg "$relay_name | 入站:$relay_type:$relay_port -> 出站:$relay_target_type:$relay_target:$relay_target_port"
        fi
    done
    line_sep
}

relay_show_existing_nodes() {
    msg
    section_title "当前普通代理配置"
    if ! ls "$is_conf_dir"/*.json >/dev/null 2>&1; then
        msg "暂无普通节点配置."
        line_sep
        return
    fi

    relay_has_node=
    for relay_file in "$is_conf_dir"/*.json; do
        relay_name=$(basename "$relay_file")
        [[ "$relay_name" == ${relay_config_prefix}*.json ]] && continue
        relay_type=$(jq -r '.inbounds[0].type // "unknown"' "$relay_file" 2>/dev/null)
        relay_port=$(jq -r '.inbounds[0].listen_port // "unknown"' "$relay_file" 2>/dev/null)
        msg "$relay_name | $relay_type | :$relay_port"
        relay_has_node=1
    done

    [[ ! "$relay_has_node" ]] && msg "暂无普通节点配置."
    line_sep
}

relay_add_chain_menu() {
    relay_collect_chain_config
    relay_write_chain_config
}

relay_is_recommended_protocol() {
    case "$1" in
    VLESS-REALITY | Hysteria2 | TUIC | Shadowsocks | Trojan | AnyTLS)
        return 0
        ;;
    esac
    return 1
}

relay_tls_host_used() {
    [[ ! $relay_inbound_host ]] && return 1
    if [[ -f "$is_caddy_conf/$relay_inbound_host.conf" ]]; then
        relay_replace_host=$(jq -r '.inbounds[0].transport.headers.host // empty' "$relay_replace_file" 2>/dev/null)
        [[ "$relay_replace_host" == "$relay_inbound_host" ]] || return 0
    fi
    for relay_file in "$is_conf_dir"/*.json; do
        [[ -f "$relay_file" ]] || continue
        [[ "$relay_file" == "$relay_replace_file" ]] && continue
        relay_existing_host=$(jq -r '.inbounds[0].transport.headers.host // empty' "$relay_file" 2>/dev/null)
        [[ "$relay_existing_host" == "$relay_inbound_host" ]] && return 0
    done
    return 1
}

relay_check_caddy_config() {
    [[ $relay_uses_caddy_tls ]] || return
    relay_caddy_error=
    [[ -x "$is_caddy_bin" ]] || {
        relay_caddy_error="Caddy 未安装，无法启用 TLS 链式转发."
        return 1
    }
    "$is_caddy_bin" validate --config "$is_caddyfile" --adapter caddyfile &>/dev/null || {
        relay_caddy_error="Caddy 配置检查失败."
        return 1
    }
}

relay_rollback_chain_config() {
    rm -f "$relay_file"
    [[ $relay_backup_file ]] && mv -f "$relay_backup_file" "$relay_replace_file"
}

relay_collect_chain_config() {
    relay_inbound_protocols=()
    relay_recommended_protocols=(VLESS-REALITY Hysteria2 TUIC Shadowsocks Trojan AnyTLS)

    msg "\n请选择入站协议"
    for relay_protocol in "${relay_recommended_protocols[@]}"; do
        relay_inbound_protocols+=("$relay_protocol")
        msg "${#relay_inbound_protocols[@]}. $relay_protocol"
    done
    relay_advanced_choice=$((${#relay_inbound_protocols[@]} + 1))
    msg "$relay_advanced_choice. 进阶协议"

    ask string relay_choice "请选择:"
    [[ ! "$relay_choice" =~ ^[0-9]+$ ]] && err "无效选择."
    [[ "$relay_choice" -lt 1 || "$relay_choice" -gt "$relay_advanced_choice" ]] && err "无效选择."
    if [[ "$relay_choice" -eq "$relay_advanced_choice" ]]; then
        relay_inbound_protocols=()
        msg "\n请选择进阶入站协议"
        for relay_protocol in "${protocol_list[@]}"; do
            [[ "$relay_protocol" == "Direct" ]] && continue
            relay_is_recommended_protocol "$relay_protocol" && continue
            relay_inbound_protocols+=("$relay_protocol")
            msg "${#relay_inbound_protocols[@]}. $relay_protocol"
        done

        ask string relay_choice "请选择:"
        [[ ! "$relay_choice" =~ ^[0-9]+$ ]] && err "无效选择."
        [[ "$relay_choice" -lt 1 || "$relay_choice" -gt "${#relay_inbound_protocols[@]}" ]] && err "无效选择."
    fi
    relay_inbound_protocol="${relay_inbound_protocols[$((relay_choice - 1))]}"

    ask string relay_target_link "请粘贴目标代理链接:"
    [[ -z "$relay_target_link" ]] && err "目标代理链接不能为空."

    echo -ne "本地监听端口，回车随机:"
    read -r relay_listen_port
    if [[ -z "$relay_listen_port" ]]; then
        get_port
        relay_listen_port="$tmp_port"
    fi

    [[ ! "$relay_listen_port" =~ ^[0-9]+$ ]] && err "本地端口必须是数字."
    [[ "$relay_listen_port" -lt 1 || "$relay_listen_port" -gt 65535 ]] && err "本地端口范围必须是 1-65535."
    [[ $(is_test port_used "$relay_listen_port") && "$relay_listen_port" != "$relay_allow_used_port" ]] && err "本地端口已被占用: $relay_listen_port"

    if [[ ${relay_inbound_protocol,,} == *-tls ]]; then
        relay_inbound_host=
        ask string relay_inbound_host "请输入入站域名:"
        [[ -z "$relay_inbound_host" ]] && err "$relay_inbound_protocol 需要入站域名."
        relay_tls_host_used && err "入站域名已被现有配置占用: $relay_inbound_host"
    fi

    get_uuid
    relay_inbound_uuid="$tmp_uuid"
    get_uuid
    relay_inbound_password="$tmp_uuid"
    relay_name="$(tr '[:upper:]' '[:lower:]' <<<"$relay_inbound_protocol" | tr -cd 'a-z0-9-')-$relay_listen_port"
}

relay_go_version_ok() {
    command -v go >/dev/null 2>&1 || return 1
    relay_go_version=$(go env GOVERSION 2>/dev/null | sed 's/^go//')
    [[ -z "$relay_go_version" ]] && relay_go_version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')
    relay_go_major=${relay_go_version%%.*}
    relay_go_minor=${relay_go_version#*.}
    relay_go_minor=${relay_go_minor%%.*}
    [[ -z "$relay_go_major" || -z "$relay_go_minor" ]] && return 1
    [[ "$relay_go_major" -gt 1 || "$relay_go_major" -eq 1 && "$relay_go_minor" -ge 21 ]]
}

relay_ensure_parser() {
    [[ -x "$relay_parser_bin" ]] && return

    relay_bundled_parser="$is_sh_dir/bin/relay-parser-linux-$is_arch"
    if [[ -f "$relay_bundled_parser" ]]; then
        mkdir -p "$is_core_dir/bin"
        cp -f "$relay_bundled_parser" "$relay_parser_bin"
        chmod +x "$relay_parser_bin"
        return
    fi

    relay_parser_url="https://github.com/${is_sh_repo}/releases/latest/download/relay-parser-linux-${is_arch}"
    mkdir -p "$is_core_dir/bin"
    msg "下载 relay-parser > $relay_parser_url"
    if _wget -t 3 -q -O "$relay_parser_bin" "$relay_parser_url"; then
        chmod +x "$relay_parser_bin"
        return
    fi
    rm -f "$relay_parser_bin"

    if relay_go_version_ok && [[ -d "$is_sh_dir/cmd/relay-parser" ]]; then
        mkdir -p "$is_core_dir/bin"
        (cd "$is_sh_dir/cmd/relay-parser" && go build -o "$relay_parser_bin" .) || err "relay-parser 构建失败."
        return
    fi

    err "缺少 relay-parser，且无法下载预编译文件. 请稍后重试或手动下载: $relay_parser_url"
}

relay_ensure_tls_pair() {
    relay_tls_cer="$is_tls_cer"
    relay_tls_key="$is_tls_key"
    [[ -f "$relay_tls_cer" && -f "$relay_tls_key" ]] && return

    mkdir -p "$is_core_dir/bin"
    "$is_core_bin" generate tls-keypair tls -m 456 >"$is_core_dir/bin/tls.tmp"
    awk '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/' "$is_core_dir/bin/tls.tmp" >"$relay_tls_key"
    awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$is_core_dir/bin/tls.tmp" >"$relay_tls_cer"
    rm -f "$is_core_dir/bin/tls.tmp"
}

relay_build_inbound_json() {
    relay_ensure_tls_pair

    port="$relay_listen_port"
    uuid="$relay_inbound_uuid"
    password="$relay_inbound_password"
    ss_password="$relay_inbound_password"
    is_socks_user=relay
    is_socks_pass="$relay_inbound_password"
    is_dont_test_host=1
    is_dont_show_info=1
    is_test_json=1
    relay_uses_caddy_tls=
    is_new_protocol=
    is_new_json=
    is_config_file=
    is_protocol=
    net=
    net_type=
    json_str=
    host=
    path=
    is_servername=
    is_private_key=
    is_public_key=
    is_reality=
    is_add_public_key=
    is_use_tls=
    is_use_host=
    is_use_uuid=
    is_use_path=
    is_use_port=
    is_use_pass=
    is_use_method=
    is_use_servername=
    is_use_socks_user=
    is_use_socks_pass=
    is_tmp_use_type=
    is_anytls_domain=
    ss_method=

    case ${relay_inbound_protocol,,} in
    *-tls)
        host="$relay_inbound_host"
        is_dont_test_host=
        relay_uses_caddy_tls=1
        add "$relay_inbound_protocol" "$host" "$uuid" auto
        ;;
    *reality*)
        add "$relay_inbound_protocol" "$port" "$uuid"
        ;;
    trojan* | hysteria2* | anytls*)
        add "$relay_inbound_protocol" "$port" "$password"
        ;;
    shadowsocks)
        ss_method="$is_random_ss_method"
        ss_password=$(get ss2022)
        relay_inbound_password="$ss_password"
        add "$relay_inbound_protocol" "$port" "$ss_password" "$ss_method"
        ;;
    socks)
        add "$relay_inbound_protocol" "$port" "$is_socks_user" "$is_socks_pass"
        ;;
    *)
        add "$relay_inbound_protocol" "$port" "$uuid"
        ;;
    esac

    [[ -z "$is_new_json" ]] && err "无法生成入站协议配置: $relay_inbound_protocol"

    relay_inbound_json=$(jq -c \
        --argjson listen_port "$relay_listen_port" \
        '.inbounds[0]
        | .tag = "relay-in"
        | .listen_port = $listen_port' \
        <<<$is_new_json)

    is_test_json=
    is_dont_test_host=
    is_dont_show_info=
    is_no_auto_tls=
}

relay_write_chain_config() {
    relay_ensure_parser
    relay_outbound_json=$("$relay_parser_bin" "$relay_target_link") || err "目标代理链接解析失败."
    relay_build_inbound_json

    relay_file="$is_conf_dir/${relay_config_prefix}${relay_name}.json"
    [[ -f "$relay_file" && "$relay_file" != "$relay_replace_file" ]] && err "配置已存在: $(basename "$relay_file")"
    relay_tmp_file="$relay_file.tmp.$$"
    relay_backup_file=
    relay_old_caddy_host=
    relay_inbound_tag="relay-in-$relay_name"
    relay_outbound_tag="relay-target-$relay_name"

    jq \
        --argjson inbound "$relay_inbound_json" \
        --argjson outbound "$relay_outbound_json" \
        --arg inbound_tag "$relay_inbound_tag" \
        --arg outbound_tag "$relay_outbound_tag" \
        '($inbound | .tag = $inbound_tag) as $in
        | ($outbound | .tag = $outbound_tag) as $out
        | {inbounds:[$in],outbounds:[$out],route:{rules:[{inbound:[$inbound_tag],action:"route",outbound:$outbound_tag}]}}' <<<'{}' >"$relay_tmp_file"

    if [[ $relay_replace_file ]]; then
        relay_backup_file="$relay_replace_file.bak.$$"
        relay_old_caddy_host=$(jq -r '.inbounds[0].transport.headers.host // empty' "$relay_replace_file" 2>/dev/null)
        cp -f "$relay_replace_file" "$relay_backup_file" || {
            rm -f "$relay_tmp_file"
            err "备份链式转发配置失败."
        }
        [[ "$relay_file" != "$relay_replace_file" ]] && rm -f "$relay_replace_file"
    fi
    mv -f "$relay_tmp_file" "$relay_file" || {
        [[ $relay_backup_file ]] && mv -f "$relay_backup_file" "$relay_replace_file"
        err "写入链式转发配置失败."
    }

    "$is_core_bin" check -c "$is_config_json" -C "$is_conf_dir" || {
        relay_rollback_chain_config
        err "sing-box 配置检查失败，已回滚链式转发配置."
    }

    [[ $relay_uses_caddy_tls ]] && {
        create caddy "$net"
        relay_check_caddy_config || {
            rm -f "$is_caddy_conf/$host.conf" "$is_caddy_conf/$host.conf.add"
            relay_rollback_chain_config
            err "${relay_caddy_error:-Caddy 配置检查失败.} 已回滚链式转发配置."
        }
    }
    [[ $relay_backup_file ]] && rm -f "$relay_backup_file"
    if [[ $relay_old_caddy_host && $relay_old_caddy_host != "$host" && -f "$is_caddy_conf/$relay_old_caddy_host.conf" ]]; then
        rm -rf "$is_caddy_conf/$relay_old_caddy_host.conf" "$is_caddy_conf/$relay_old_caddy_host.conf.add"
        [[ ! $relay_uses_caddy_tls ]] && manage restart caddy &
    fi

    relay_print_client_url
    msg "正在重启 $is_core_name 应用配置；如果当前连接经由 $is_core_name，可能会短暂断开."
    manage restart
}

relay_print_client_url() {
    get_ip
    msg
    section_title "relay-$relay_name 节点信息"
    msg "协议: $relay_inbound_protocol"
    if [[ $relay_uses_caddy_tls ]]; then
        msg "域名: $relay_inbound_host"
        msg "入口端口: $is_https_port"
        msg "后端端口: $relay_listen_port"
    else
        msg "地址: $ip"
        msg "端口: $relay_listen_port"
    fi
    msg "UUID: $relay_inbound_uuid"
    msg "密码: $relay_inbound_password"
    msg "配置文件: ${relay_config_prefix}${relay_name}.json"
    if [[ $relay_uses_caddy_tls ]]; then
        msg "请在 AWS 安全组和系统防火墙放行 Caddy HTTPS 端口 TCP/$is_https_port"
    else
        msg "请在 AWS 安全组和系统防火墙放行该入站协议需要的 TCP 或 UDP/$relay_listen_port"
    fi

    [[ ! $relay_uses_caddy_tls ]] && is_https_port="$relay_listen_port"
    url_qr url "${relay_config_prefix}${relay_name}.json"
}

relay_change_chain_config() {
    if ! ls "$is_conf_dir"/${relay_config_prefix}*.json >/dev/null 2>&1; then
        msg "暂无链式转发配置."
        return
    fi

    is_config_file=
    get file "$relay_config_prefix"
    relay_replace_file="$is_conf_dir/$is_config_file"
    relay_allow_used_port=$(jq -r '.inbounds[0].listen_port // empty' "$relay_replace_file")
    relay_collect_chain_config
    relay_write_chain_config
    relay_replace_file=
    relay_allow_used_port=
}

relay_delete_chain_config() {
    if ! ls "$is_conf_dir"/${relay_config_prefix}*.json >/dev/null 2>&1; then
        msg "暂无链式转发配置."
        return
    fi
    del "$relay_config_prefix"
}
