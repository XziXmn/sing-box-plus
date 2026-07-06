relay_config_prefix=relay-chain-
relay_parser_bin="$is_core_dir/bin/relay-parser"

relay_menu() {
    msg
    section_title "链式转发"
    msg "1. 添加配置"
    msg "2. 删除配置"
    msg "0. 退出"
    ask string relay_choice "请选择:"

    case "$relay_choice" in
    1)
        relay_add_chain_menu
        ;;
    2)
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
        relay_target_type=$(jq -r '.outbounds[0].type // "unknown"' "$relay_file" 2>/dev/null)
        relay_target=$(jq -r '.outbounds[0].server // "unknown"' "$relay_file" 2>/dev/null)
        relay_target_port=$(jq -r '.outbounds[0].server_port // "unknown"' "$relay_file" 2>/dev/null)
        msg "$relay_name | 入站:$relay_type:$relay_port -> 出站:$relay_target_type:$relay_target:$relay_target_port"
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
    msg "\n请选择入站协议"
    relay_inbound_protocols=()
    for relay_protocol in "${protocol_list[@]}"; do
        [[ "$relay_protocol" == "Direct" ]] && continue
        relay_inbound_protocols+=("$relay_protocol")
        msg "${#relay_inbound_protocols[@]}. $relay_protocol"
    done

    ask string relay_choice "请选择:"
    [[ ! "$relay_choice" =~ ^[0-9]+$ ]] && err "无效选择."
    [[ "$relay_choice" -lt 1 || "$relay_choice" -gt "${#relay_inbound_protocols[@]}" ]] && err "无效选择."
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
    [[ $(is_test port_used "$relay_listen_port") ]] && err "本地端口已被占用: $relay_listen_port"

    if [[ ${relay_inbound_protocol,,} == *-tls ]]; then
        ask string relay_inbound_host "请输入入站域名:"
        [[ -z "$relay_inbound_host" ]] && err "$relay_inbound_protocol 需要入站域名."
    fi

    get_uuid
    relay_inbound_uuid="$tmp_uuid"
    get_uuid
    relay_inbound_password="$tmp_uuid"
    relay_name="$(tr '[:upper:]' '[:lower:]' <<<"$relay_inbound_protocol" | tr -cd 'a-z0-9-')-$relay_listen_port"

    relay_write_chain_config
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
    is_new_protocol=
    is_new_json=
    is_config_file=
    json_str=
    host=
    path=
    is_servername=
    is_anytls_domain=
    ss_method=

    case ${relay_inbound_protocol,,} in
    *-tls)
        host="$relay_inbound_host"
        is_no_auto_tls=1
        add "$relay_inbound_protocol" "$host" "$uuid" auto
        ;;
    *reality*)
        add "$relay_inbound_protocol" "$port" "$uuid" auto
        ;;
    trojan* | hysteria2* | anytls*)
        add "$relay_inbound_protocol" "$port" "$password"
        ;;
    shadowsocks)
        add "$relay_inbound_protocol" "$port" "$ss_password"
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
        --arg cer "$relay_tls_cer" \
        --arg key "$relay_tls_key" \
        '.inbounds[0]
        | .tag = "relay-in"
        | .listen = "::"
        | .listen_port = $listen_port
        | if .tls.enabled == true then .tls.certificate_path = $cer | .tls.key_path = $key else . end' \
        <<<$is_new_json)

    is_test_json=
    is_dont_show_info=
    is_no_auto_tls=
}

relay_write_chain_config() {
    relay_ensure_parser
    relay_outbound_json=$("$relay_parser_bin" "$relay_target_link") || err "目标代理链接解析失败."
    relay_build_inbound_json

    relay_file="$is_conf_dir/${relay_config_prefix}${relay_name}.json"
    [[ -f "$relay_file" ]] && err "配置已存在: $(basename "$relay_file")"
    relay_inbound_tag="relay-in-$relay_name"
    relay_outbound_tag="relay-target-$relay_name"

    jq \
        --argjson inbound "$relay_inbound_json" \
        --argjson outbound "$relay_outbound_json" \
        --arg inbound_tag "$relay_inbound_tag" \
        --arg outbound_tag "$relay_outbound_tag" \
        '($inbound | .tag = $inbound_tag) as $in
        | ($outbound | .tag = $outbound_tag) as $out
        | {inbounds:[$in],outbounds:[$out],route:{rules:[{inbound:[$inbound_tag],action:"route",outbound:$outbound_tag}]}}' <<<'{}' >"$relay_file"

    "$is_core_bin" check -c "$is_config_json" -C "$is_conf_dir" || {
        rm -f "$relay_file"
        err "sing-box 配置检查失败，已回滚链式转发配置."
    }

    manage restart
    relay_print_client_url
}

relay_print_client_url() {
    get_ip
    msg
    section_title "relay-$relay_name 节点信息"
    msg "协议: $relay_inbound_protocol"
    msg "地址: $ip"
    msg "端口: $relay_listen_port"
    msg "UUID: $relay_inbound_uuid"
    msg "密码: $relay_inbound_password"
    msg "配置文件: ${relay_config_prefix}${relay_name}.json"
    msg "请在 AWS 安全组和系统防火墙放行该入站协议需要的 TCP 或 UDP/$relay_listen_port"

    is_https_port="$relay_listen_port"
    url_qr url "${relay_config_prefix}${relay_name}.json"
}

relay_delete_chain_config() {
    relay_show_configs
    if ! ls "$is_conf_dir"/${relay_config_prefix}*.json >/dev/null 2>&1; then
        return
    fi

    ask string relay_delete_name "请输入要删除的配置文件名:"
    [[ "$relay_delete_name" != ${relay_config_prefix}*.json ]] && err "只能删除 ${relay_config_prefix}*.json 配置."

    relay_delete_path="$is_conf_dir/$relay_delete_name"
    [[ ! -f "$relay_delete_path" ]] && err "配置不存在: $relay_delete_name"

    rm -f "$relay_delete_path"
    "$is_core_bin" check -c "$is_config_json" -C "$is_conf_dir" || err "sing-box 配置检查失败，请检查剩余配置."
    manage restart
    msg "已删除链式转发配置: $relay_delete_name"
}
