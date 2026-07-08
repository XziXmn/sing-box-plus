# 介绍

sing-box-plus 是个人修改版本，用于 sing-box 一键安装、管理与链式转发。

# 特点

## 当前版本特性

- 新增链式转发管理，可通过 `sb` 主菜单、`sing-box relay` 或 `sbb` 进入
- 支持粘贴目标代理链接，自动生成本机入站到目标出站的链式配置
- 链式转发配置文件使用 `relay-chain-*.json` 命名，便于区分普通节点
- 自动展示当前链式转发配置和已有普通节点
- 链式转发支持按字段修改入站协议、端口、域名、密码、UUID、加密方式、用户名和出站链接
- 主菜单新增 `BBR配置`，支持系统 BBR、BBRv3 脚本入口和亚太 TCP 调优入口

## 基础能力

- 快速安装
- 无敌好用
- 零学习成本
- 自动化 TLS
- 简化所有流程
- 兼容 sing-box 命令
- 强大的快捷参数
- 支持链式转发管理
- 支持 `sbb` 快捷入口
- 支持所有常用协议
- 一键添加 VLESS-REALITY (默认)
- 一键添加 TUIC
- 一键添加 Trojan
- 一键添加 Hysteria2
- 一键添加 AnyTLS
- 一键添加 Shadowsocks 2022
- 一键添加 VMess-(TCP/HTTP/QUIC)
- 一键添加 VMess-(WS/H2/HTTPUpgrade)-TLS
- 一键添加 VLESS-(WS/H2/HTTPUpgrade)-TLS
- 一键添加 Trojan-(WS/H2/HTTPUpgrade)-TLS
- BBR 配置与 BBRv3 入口
- 一键更改伪装网站
- 一键更改 (端口/UUID/密码/域名/路径/加密方式/SNI/等...)
- 还有更多...

# 设计理念

设计理念为：**高效率，超快速，极易用**

脚本以 **多配置同时运行** 为核心设计

并且专门优化了，添加、更改、查看、删除、这四项常用功能

你只需要一条命令即可完成 添加、更改、查看、删除、等操作

例如，添加一个配置仅需不到 1 秒！瞬间完成添加！其他操作亦是如此！

脚本的参数非常高效率并且超级易用，请掌握参数的使用

# 文档

本仓库：https://github.com/XziXmn/sing-box-plus

# 安装

## 从发行版安装

默认下载 GitHub Release 中的 `code.tar.gz`，适合日常安装与更新：

使用 root 用户执行：

```bash
wget -O install.sh https://raw.githubusercontent.com/XziXmn/sing-box-plus/main/install.sh
bash install.sh
```

发行版安装包会内置 `relay-parser` 预编译文件，不需要在服务器安装 Go。

## 从脚本安装

直接下载 `main` 分支源码，可以体验最新特性：

```bash
wget -O install-beta.sh https://raw.githubusercontent.com/XziXmn/sing-box-plus/main/install-beta.sh
bash install-beta.sh
```

脚本安装包不内置 `relay-parser` 预编译文件，安装或首次使用链式转发时会自动下载对应架构的独立 `relay-parser`。

也可以克隆仓库后使用本地安装：

```bash
git clone https://github.com/XziXmn/sing-box-plus.git
cd sing-box-plus
bash install.sh --local-install
```

安装完成后会创建以下命令：

```bash
sing-box
sb
sbb
```

## 已安装原版脚本的机器

当前安装脚本不会静默覆盖已安装的原版脚本。

如果已经安装的是 sing-box-plus，再次执行安装脚本会自动更新脚本文件，不会提示迁移配置。

如果机器上已经存在 `/etc/sing-box`、`/usr/local/bin/sing-box`、脚本目录或配置目录，直接执行安装脚本时会先提示是否迁移现有配置到 sing-box-plus。

确认迁移后，脚本会保留现有配置并替换脚本文件：

```bash
cp -a /etc/sing-box /root/sing-box-backup-$(date +%Y%m%d-%H%M%S)
wget -O install.sh https://raw.githubusercontent.com/XziXmn/sing-box-plus/main/install.sh
bash install.sh
```

如果选择不迁移配置，脚本会继续提示当前 sing-box 脚本与新脚本冲突，询问是否删除已安装脚本并全新安装 sing-box-plus。确认后会先把旧安装备份到 `/root/sing-box-plus-backup-*`，再删除旧脚本并安装新脚本。

也可以使用非交互迁移模式，直接迁移配置：

```bash
bash install.sh --migrate
```

迁移会：

- 保留现有 `/etc/sing-box/conf` 配置
- 保留现有 `/etc/sing-box/config.json`
- 备份旧安装到 `/root/sing-box-plus-backup-*`
- 卸载原 sing-box 脚本
- 安装 sing-box-plus 脚本
- 重建 `sing-box`、`sb`、`sbb` 命令入口
- 尝试把旧 Caddy 配置目录 `/etc/caddy/233boy` 迁移到 `/etc/caddy/sing-box-plus`

如果不想迁移，也可以先备份配置，再卸载原脚本后全新安装。

# 使用教程

## 主菜单

```bash
sb
```

主菜单会展示当前普通代理配置、链式转发配置和 BBR 状态，并提供添加、修改、删除、链式转发、BBR配置、更新等入口。

## 链式转发

从主菜单选择 `链式转发`，或直接执行：

```bash
sbb
```

也可以使用完整命令：

```bash
sing-box relay
```

进入链式转发后：

1. 选择 `添加配置`
2. 选择本机入站协议
3. 粘贴目标代理链接
4. 输入本地监听端口，或直接回车随机
5. 按提示放行防火墙和云服务器安全组端口

链式转发配置会保存为：

```bash
/etc/sing-box/conf/relay-chain-*.json
```

链式转发的 `更改配置` 会按当前入站协议展开可修改项：

- 入站协议
- 入站端口
- 入站域名，仅 TLS/有域名配置显示
- 密码，仅支持密码的协议显示
- UUID，仅支持 UUID 的协议显示
- 加密方式，仅 Shadowsocks 显示
- 用户名，仅 Socks 显示
- 出站链接
- 全量修改

其中 `更改出站链接` 只会重新解析并替换出站配置，不会改动原入站端口、密码、UUID 或 TLS 配置。

## BBR 配置

从主菜单选择 `BBR配置`，或直接执行：

```bash
sing-box bbr
```

可用选项：

1. 启用系统自带 BBR
2. 查看 BBR 状态
3. 安装/更新 BBRv3 标准内核
4. 运行 BBRv3 脚本
5. 亚太机器 TCP 调优

系统自带 BBR 会优先检测当前系统实际可用的拥塞控制算法；如果 `tcp_available_congestion_control` 中存在 `bbr`，即可启用并写入 `/etc/sysctl.d/99-sing-box-plus-bbr.conf`。

BBRv3 和亚太机器 TCP 调优会调用 BBRv3 脚本。脚本会先检测 `/tmp/sing-box-plus-bbrv3.sh` 是否存在，不存在或为空时才下载。

## 常用命令

```bash
sing-box add              # 添加普通代理配置
sing-box info             # 查看配置
sing-box url <name>       # 查看节点 URL
sing-box qr <name>        # 查看二维码
sing-box status           # 查看运行状态
sing-box restart          # 重启 sing-box
sing-box update.sh        # 更新脚本
sing-box export           # 导出配置 base64 文本到 /root
sing-box import-export <text|file> # 导入导出的 base64 配置文本
sing-box uninstall        # 卸载脚本
```

导出配置会生成：

```bash
/root/sing-box-plus-config-YYYYmmdd-HHMMSS.b64.txt
```

导出内容包括 `/etc/sing-box/config.json`、`/etc/sing-box/conf`、TLS 证书文件，以及 sing-box-plus 使用的 Caddy 配置。

这个文件本身就是完整配置包的 base64 文本，方便在多台服务器之间直接复制迁移。
导出完成后，脚本也会在终端直接输出同一段 base64 文本。

导入时使用：

```bash
sing-box import-export
```

执行后直接粘贴 `.b64.txt` 里的整段 base64 文本即可；也可以使用 `sing-box import-export /root/sing-box-plus-config-YYYYmmdd-HHMMSS.b64.txt` 从文件导入。

导入会覆盖当前配置。脚本会先检查配置包内的端口冲突、协议端口冲突，以及目标端口是否被其他进程占用；通过后再把现有配置备份到 `/root/sing-box-plus-import-backup-YYYYmmdd-HHMMSS`，并要求确认后才执行覆盖。

# 帮助

使用：`sing-box help`

```
sing-box-plus script v0.1.12 personal modified version
Usage: sing-box [options]... [args]...

基本:
   v, version                                      显示当前版本
   ip                                              返回当前主机的 IP
   pbk                                             同等于 sing-box generate reality-keypair
   get-port                                        返回一个可用的端口
   ss2022                                          返回一个可用于 Shadowsocks 2022 的密码

一般:
   a, add [protocol] [args... | auto]              添加配置
   c, change [name] [option] [args... | auto]      更改配置
   d, del [name]                                   删除配置**
   i, info [name]                                  查看配置
   qr [name]                                       二维码信息
   url [name]                                      URL 信息
   log                                             查看日志
更改:
   full [name] [...]                               更改多个参数
   id [name] [uuid | auto]                         更改 UUID
   host [name] [domain]                            更改域名
   port [name] [port | auto]                       更改端口
   path [name] [path | auto]                       更改路径
   passwd [name] [password | auto]                 更改密码
   key [name] [Private key | auto] [Public key]    更改密钥
   method [name] [method | auto]                   更改加密方式
   sni [name] [ ip | domain]                       更改 serverName
   new [name] [...]                                更改协议
   web [name] [domain]                             更改伪装网站

进阶:
   dns [...]                                       设置 DNS
   dd, ddel [name...]                              删除多个配置**
   fix [name]                                      修复一个配置
   fix-all                                         修复全部配置
   fix-caddyfile                                   修复 Caddyfile
   fix-config.json                                 修复 config.json
   export [dir]                                    导出配置 base64 文本
   import-export [text|file]                       导入 base64 配置文本
   import                                          导入 sing-box/v2ray 脚本配置

管理:
   relay                                           链式转发管理
   sbb                                             链式转发管理
   un, uninstall                                   卸载
   u, update [core | sh | caddy] [ver]             更新
   U, update.sh                                    更新脚本
   s, status                                       运行状态
   start, stop, restart [caddy]                    启动, 停止, 重启
   t, test                                         测试运行
   reinstall                                       重装脚本

测试:
   debug [name]                                    显示一些 debug 信息, 仅供参考
   gen [...]                                       同等于 add, 但只显示 JSON 内容, 不创建文件, 测试使用
   no-auto-tls [...]                               同等于 add, 但禁止自动配置 TLS, 可用于 *TLS 相关协议
其他:
   bbr                                             BBR 设置
   bin [...]                                       运行 sing-box 命令, 例如: sing-box bin help
   [...] [...]                                     兼容绝大多数的 sing-box 命令, 例如: sing-box generate uuid
   h, help                                         显示此帮助界面

谨慎使用 del, ddel, 此选项会直接删除配置; 无需确认
反馈问题) https://github.com/XziXmn/sing-box-plus/issues
文档(doc) https://github.com/XziXmn/sing-box-plus
```
