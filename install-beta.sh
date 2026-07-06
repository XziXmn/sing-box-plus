#!/bin/bash

repo=XziXmn/sing-box-plus
tmpdir=$(mktemp -d)
archive=$tmpdir/code.tar.gz
srcdir=$tmpdir/src

cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT

err() {
    echo "错误! $*" >&2
    exit 1
}

cmd=$(type -P wget || true)
[[ ! $cmd ]] && err "缺少 wget, 请先安装 wget."

mkdir -p "$srcdir"
echo "下载 sing-box-plus beta 源码 > https://github.com/${repo}/archive/refs/heads/main.tar.gz"
wget --no-check-certificate -q -O "$archive" "https://github.com/${repo}/archive/refs/heads/main.tar.gz" || err "下载 beta 源码失败."
tar zxf "$archive" --strip-components 1 -C "$srcdir" || err "解压 beta 源码失败."

cd "$srcdir" || exit 1
bash install.sh --local-install "$@"
