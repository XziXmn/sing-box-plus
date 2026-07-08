export_config() {
    local export_dir export_file export_base tmpdir archive_file
    export_dir=${1:-/root}
    [[ -d "$export_dir" ]] || mkdir -p "$export_dir" || err "无法创建导出目录: $export_dir"

    export_base=sing-box-plus-config-$(date +%Y%m%d-%H%M%S)
    export_file=$export_dir/$export_base.b64.txt

    tmpdir=$(mktemp -d) || err "创建临时目录失败."
    archive_file=$tmpdir/$export_base.tar.gz
    mkdir -p "$tmpdir/$export_base/sing-box/conf" "$tmpdir/$export_base/caddy/sing-box-plus"

    [[ -f "$is_config_json" ]] && cp -a "$is_config_json" "$tmpdir/$export_base/sing-box/config.json"
    [[ -d "$is_conf_dir" ]] && cp -a "$is_conf_dir/." "$tmpdir/$export_base/sing-box/conf/"
    [[ -f "$is_core_dir/bin/tls.cer" ]] && cp -a "$is_core_dir/bin/tls.cer" "$tmpdir/$export_base/sing-box/tls.cer"
    [[ -f "$is_core_dir/bin/tls.key" ]] && cp -a "$is_core_dir/bin/tls.key" "$tmpdir/$export_base/sing-box/tls.key"
    [[ -d "$is_caddy_conf" ]] && cp -a "$is_caddy_conf/." "$tmpdir/$export_base/caddy/sing-box-plus/"
    [[ -f "$is_caddyfile" ]] && cp -a "$is_caddyfile" "$tmpdir/$export_base/caddy/Caddyfile"

    tar -C "$tmpdir" -czf "$archive_file" "$export_base" || {
        rm -rf "$tmpdir"
        err "导出配置失败."
    }
    base64 -w 0 "$archive_file" >"$export_file" || {
        rm -rf "$tmpdir"
        err "生成 base64 配置文本失败."
    }
    echo >>"$export_file"
    rm -rf "$tmpdir"
    _green "\n配置已导出: $export_file\n"
    msg "base64 配置文本:"
    cat "$export_file"
    msg
    msg "导入命令: $is_core import-export $export_file"
}

import_export_config() {
    local import_input tmpdir archive_file import_root backup_dir confirm

    import_input=$1
    if [[ ! $import_input ]]; then
        echo -ne "请粘贴 base64 配置文本，或输入导入文件路径: "
        read -r import_input
    fi
    [[ $import_input ]] || err "导入内容不能为空."

    tmpdir=$(mktemp -d) || err "创建临时目录失败."
    archive_file=$tmpdir/import.tar.gz

    if [[ -f "$import_input" ]]; then
        base64 -d "$import_input" >"$archive_file" 2>/dev/null
    else
        printf '%s' "$import_input" | base64 -d >"$archive_file" 2>/dev/null
    fi
    [[ $? -eq 0 ]] || {
        rm -rf "$tmpdir"
        err "导入内容不是有效的 base64 配置文本."
    }
    tar -tzf "$archive_file" >/dev/null 2>&1 || {
        rm -rf "$tmpdir"
        err "导入文件不是有效的 sing-box-plus 配置包."
    }
    tar -tzf "$archive_file" | grep -Eq '(^/|(^|/)\.\.(/|$))' && {
        rm -rf "$tmpdir"
        err "导入文件包含不安全路径."
    }
    tar -xzf "$archive_file" -C "$tmpdir" || {
        rm -rf "$tmpdir"
        err "解压导入配置失败."
    }

    import_root=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d -name 'sing-box-plus-config-*' | head -n 1)
    [[ -d "$import_root/sing-box" ]] || {
        rm -rf "$tmpdir"
        err "导入文件缺少 sing-box 配置目录."
    }
    [[ -f "$import_root/sing-box/config.json" && -d "$import_root/sing-box/conf" ]] || {
        rm -rf "$tmpdir"
        err "导入文件不是完整的 sing-box-plus 配置包."
    }
    validate_import_config "$import_root"

    backup_dir=/root/sing-box-plus-import-backup-$(date +%Y%m%d-%H%M%S)
    warn "导入会覆盖当前 sing-box-plus 配置."
    msg "覆盖前会备份当前配置到: $backup_dir"
    echo -ne "确认导入? [y/N]: "
    read -r confirm
    [[ ${confirm,,} == y ]] || {
        rm -rf "$tmpdir"
        msg "已取消导入."
        return
    }

    backup_current_config "$backup_dir"
    restore_export_config "$import_root"
    rm -rf "$tmpdir"

    manage restart &
    [[ $is_caddy ]] && manage restart caddy &
    _green "\n配置导入完成. 已备份原配置到: $backup_dir\n"
}

validate_import_config() {
    local import_root=$1 rows_file current_ports_file conflict used_conflict conf_file conf_name port
    conflict=
    used_conflict=
    type -P jq >/dev/null 2>&1 || err "缺少 jq，无法校验导入配置."

    rows_file=$(mktemp) || err "创建临时文件失败."
    current_ports_file=$(mktemp) || {
        rm -f "$rows_file"
        err "创建临时文件失败."
    }

    if ls "$import_root/sing-box/conf"/*.json >/dev/null 2>&1; then
        for conf_file in "$import_root/sing-box/conf"/*.json; do
            conf_name=$(basename "$conf_file")
            jq -e . "$conf_file" >/dev/null 2>&1 || {
                rm -f "$rows_file" "$current_ports_file"
                err "导入配置不是有效 JSON: $conf_name"
                return 1
            }
            jq -r --arg file "$conf_name" '.inbounds[]? | select(.listen_port != null) | [$file, (.type // "unknown"), (.listen_port | tostring)] | @tsv' "$conf_file" >>"$rows_file"
        done
    fi

    conflict=$(awk -F '\t' '
        {
            count[$3]++
            item[$3] = item[$3] "\n  - " $1 " | " $2 " | :" $3
        }
        END {
            for (port in count) {
                if (count[port] > 1) {
                    print "端口冲突: :" port item[port]
                }
            }
        }
    ' "$rows_file")
    [[ $conflict ]] && {
        rm -f "$rows_file" "$current_ports_file"
        msg "$conflict"
        err "导入配置存在端口或协议冲突."
        return 1
    }

    if [[ -d "$is_conf_dir" ]] && ls "$is_conf_dir"/*.json >/dev/null 2>&1; then
        for conf_file in "$is_conf_dir"/*.json; do
            jq -r '.inbounds[]? | select(.listen_port != null) | .listen_port' "$conf_file" 2>/dev/null >>"$current_ports_file"
        done
    fi

    while IFS=$'\t' read -r conf_name _ port; do
        [[ $port ]] || continue
        if [[ $(is_test port_used "$port") && ! $(grep -x "$port" "$current_ports_file") ]]; then
            used_conflict="${used_conflict}\n  - $conf_name | :$port"
        fi
    done <"$rows_file"

    rm -f "$rows_file" "$current_ports_file"
    [[ $used_conflict ]] && {
        msg "端口已被其他进程占用:${used_conflict}"
        err "导入配置端口不可用."
        return 1
    }
    return 0
}

backup_current_config() {
    local backup_dir=$1
    mkdir -p "$backup_dir/sing-box/conf" "$backup_dir/caddy/sing-box-plus" || err "创建备份目录失败: $backup_dir"

    [[ -f "$is_config_json" ]] && cp -a "$is_config_json" "$backup_dir/sing-box/config.json"
    [[ -d "$is_conf_dir" ]] && cp -a "$is_conf_dir/." "$backup_dir/sing-box/conf/"
    [[ -f "$is_core_dir/bin/tls.cer" ]] && cp -a "$is_core_dir/bin/tls.cer" "$backup_dir/sing-box/tls.cer"
    [[ -f "$is_core_dir/bin/tls.key" ]] && cp -a "$is_core_dir/bin/tls.key" "$backup_dir/sing-box/tls.key"
    [[ -f "$is_caddyfile" ]] && cp -a "$is_caddyfile" "$backup_dir/caddy/Caddyfile"
    [[ -d "$is_caddy_conf" ]] && cp -a "$is_caddy_conf/." "$backup_dir/caddy/sing-box-plus/"
}

restore_export_config() {
    local import_root=$1

    mkdir -p "$is_core_dir/bin" "$is_conf_dir" || err "创建 sing-box 配置目录失败."
    [[ -f "$import_root/sing-box/config.json" ]] && cp -a "$import_root/sing-box/config.json" "$is_config_json"
    rm -rf "$is_conf_dir"
    mkdir -p "$is_conf_dir" || err "创建 sing-box conf 目录失败."
    [[ -d "$import_root/sing-box/conf" ]] && cp -a "$import_root/sing-box/conf/." "$is_conf_dir/"
    [[ -f "$import_root/sing-box/tls.cer" ]] && cp -a "$import_root/sing-box/tls.cer" "$is_core_dir/bin/tls.cer"
    [[ -f "$import_root/sing-box/tls.key" ]] && cp -a "$import_root/sing-box/tls.key" "$is_core_dir/bin/tls.key"

    [[ -d "$import_root/caddy" ]] || return
    mkdir -p "$is_caddy_dir" "$is_caddy_conf" || err "创建 Caddy 配置目录失败."
    [[ -f "$import_root/caddy/Caddyfile" ]] && cp -a "$import_root/caddy/Caddyfile" "$is_caddyfile"
    rm -rf "$is_caddy_conf"
    mkdir -p "$is_caddy_conf" || err "创建 Caddy 配置目录失败."
    [[ -d "$import_root/caddy/sing-box-plus" ]] && cp -a "$import_root/caddy/sing-box-plus/." "$is_caddy_conf/"
}
