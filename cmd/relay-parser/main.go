package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/MMWOrg/mmwX-plugins/proxyparser"
)

const outboundTag = "relay-target-out"

func stringValue(node map[string]any, key string) string {
	if value, ok := node[key].(string); ok {
		return value
	}
	return ""
}

func boolValue(node map[string]any, key string) bool {
	if value, ok := node[key].(bool); ok {
		return value
	}
	return false
}

func intValue(node map[string]any, key string) int {
	switch value := node[key].(type) {
	case int:
		return value
	case int64:
		return int(value)
	case float64:
		return int(value)
	case json.Number:
		i, _ := value.Int64()
		return int(i)
	}
	return 0
}

func mapValue(node map[string]any, key string) map[string]any {
	if value, ok := node[key].(map[string]any); ok {
		return value
	}
	if value, ok := node[key].(map[string]string); ok {
		out := make(map[string]any, len(value))
		for k, v := range value {
			out[k] = v
		}
		return out
	}
	return map[string]any{}
}

func stringListValue(node map[string]any, key string) []string {
	switch value := node[key].(type) {
	case []string:
		return value
	case []any:
		items := make([]string, 0, len(value))
		for _, item := range value {
			if s, ok := item.(string); ok && s != "" {
				items = append(items, s)
			}
		}
		return items
	case string:
		if value != "" {
			return []string{value}
		}
	}
	return nil
}

func firstString(node map[string]any, keys ...string) string {
	for _, key := range keys {
		if value := stringValue(node, key); value != "" {
			return value
		}
	}
	return ""
}

func baseOutbound(node map[string]any, outboundType string) (map[string]any, error) {
	server := stringValue(node, "server")
	port := intValue(node, "port")
	if server == "" || port == 0 {
		return nil, fmt.Errorf("%s target missing server or port", outboundType)
	}
	return map[string]any{
		"type":        outboundType,
		"tag":         outboundTag,
		"server":      server,
		"server_port": port,
	}, nil
}

func addTLS(outbound map[string]any, node map[string]any, force bool) {
	if !force && !boolValue(node, "tls") && len(mapValue(node, "reality-opts")) == 0 {
		return
	}

	tls := map[string]any{"enabled": true}
	if serverName := firstString(node, "servername", "sni"); serverName != "" {
		tls["server_name"] = serverName
	}
	if boolValue(node, "skip-cert-verify") {
		tls["insecure"] = true
	}
	if alpn := stringListValue(node, "alpn"); len(alpn) > 0 {
		tls["alpn"] = alpn
	}
	if fingerprint := stringValue(node, "client-fingerprint"); fingerprint != "" {
		tls["utls"] = map[string]any{
			"enabled":     true,
			"fingerprint": fingerprint,
		}
	}

	if realityOpts := mapValue(node, "reality-opts"); len(realityOpts) > 0 {
		reality := map[string]any{"enabled": true}
		if publicKey := stringValue(realityOpts, "public-key"); publicKey != "" {
			reality["public_key"] = publicKey
		}
		if shortID, ok := realityOpts["short-id"].(string); ok {
			reality["short_id"] = shortID
		}
		tls["reality"] = reality
	}

	outbound["tls"] = tls
}

func addTransport(outbound map[string]any, node map[string]any) error {
	network := strings.ToLower(stringValue(node, "network"))
	switch network {
	case "", "tcp":
		return nil
	case "ws":
		opts := mapValue(node, "ws-opts")
		transport := map[string]any{"type": "ws"}
		if path := stringValue(opts, "path"); path != "" {
			transport["path"] = path
		}
		if headers := mapValue(opts, "headers"); len(headers) > 0 {
			transport["headers"] = headers
		}
		if maxEarlyData := intValue(opts, "max-early-data"); maxEarlyData > 0 {
			transport["max_early_data"] = maxEarlyData
		}
		if header := stringValue(opts, "early-data-header-name"); header != "" {
			transport["early_data_header_name"] = header
		}
		outbound["transport"] = transport
	case "h2", "http":
		opts := mapValue(node, "h2-opts")
		transport := map[string]any{"type": "http"}
		if path := stringValue(opts, "path"); path != "" {
			transport["path"] = path
		}
		if host := stringListValue(opts, "host"); len(host) > 0 {
			transport["host"] = host
		}
		outbound["transport"] = transport
	case "grpc":
		opts := mapValue(node, "grpc-opts")
		transport := map[string]any{"type": "grpc"}
		if serviceName := stringValue(opts, "grpc-service-name"); serviceName != "" {
			transport["service_name"] = serviceName
		}
		outbound["transport"] = transport
	default:
		return fmt.Errorf("unsupported v2ray transport: %s", network)
	}
	return nil
}

func vlessOutbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "vless")
	if err != nil {
		return nil, err
	}
	outbound["uuid"] = stringValue(node, "uuid")
	if flow := stringValue(node, "flow"); flow != "" {
		outbound["flow"] = flow
	} else if len(mapValue(node, "reality-opts")) > 0 && strings.ToLower(stringValue(node, "network")) != "h2" {
		outbound["flow"] = "xtls-rprx-vision"
	}
	addTLS(outbound, node, len(mapValue(node, "reality-opts")) > 0)
	return outbound, addTransport(outbound, node)
}

func vmessOutbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "vmess")
	if err != nil {
		return nil, err
	}
	outbound["uuid"] = stringValue(node, "uuid")
	if alterID := intValue(node, "alterId"); alterID > 0 {
		outbound["alter_id"] = alterID
	}
	if security := stringValue(node, "cipher"); security != "" {
		outbound["security"] = security
	}
	addTLS(outbound, node, false)
	return outbound, addTransport(outbound, node)
}

func trojanOutbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "trojan")
	if err != nil {
		return nil, err
	}
	outbound["password"] = stringValue(node, "password")
	addTLS(outbound, node, true)
	return outbound, addTransport(outbound, node)
}

func shadowsocksOutbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "shadowsocks")
	if err != nil {
		return nil, err
	}
	outbound["method"] = stringValue(node, "cipher")
	outbound["password"] = stringValue(node, "password")
	return outbound, nil
}

func hysteria2Outbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "hysteria2")
	if err != nil {
		return nil, err
	}
	outbound["password"] = stringValue(node, "password")
	if ports := stringValue(node, "ports"); ports != "" {
		outbound["server_ports"] = []string{ports}
		if interval := intValue(node, "hop-interval"); interval > 0 {
			outbound["hop_interval"] = fmt.Sprintf("%ds", interval)
		}
	}
	if obfsType := stringValue(node, "obfs"); obfsType != "" {
		obfs := map[string]any{"type": obfsType}
		if obfsPassword := stringValue(node, "obfs-password"); obfsPassword != "" {
			obfs["password"] = obfsPassword
		}
		outbound["obfs"] = obfs
	}
	addTLS(outbound, node, true)
	return outbound, nil
}

func hysteriaOutbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "hysteria")
	if err != nil {
		return nil, err
	}
	if auth := firstString(node, "auth-str", "auth", "password"); auth != "" {
		outbound["auth_str"] = auth
	}
	addTLS(outbound, node, true)
	return outbound, nil
}

func tuicOutbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "tuic")
	if err != nil {
		return nil, err
	}
	outbound["uuid"] = stringValue(node, "uuid")
	outbound["password"] = stringValue(node, "password")
	if congestion := stringValue(node, "congestion-controller"); congestion != "" {
		outbound["congestion_control"] = congestion
	}
	if relayMode := stringValue(node, "udp-relay-mode"); relayMode != "" {
		outbound["udp_relay_mode"] = relayMode
	}
	if boolValue(node, "udp-over-stream") {
		outbound["udp_over_stream"] = true
	}
	addTLS(outbound, node, true)
	return outbound, nil
}

func anyTLSOutbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "anytls")
	if err != nil {
		return nil, err
	}
	outbound["password"] = stringValue(node, "password")
	addTLS(outbound, node, true)
	return outbound, nil
}

func socksOutbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "socks")
	if err != nil {
		return nil, err
	}
	outbound["version"] = "5"
	if username := stringValue(node, "username"); username != "" {
		outbound["username"] = username
	}
	if password := stringValue(node, "password"); password != "" {
		outbound["password"] = password
	}
	return outbound, nil
}

func httpOutbound(node map[string]any) (map[string]any, error) {
	outbound, err := baseOutbound(node, "http")
	if err != nil {
		return nil, err
	}
	if username := stringValue(node, "username"); username != "" {
		outbound["username"] = username
	}
	if password := stringValue(node, "password"); password != "" {
		outbound["password"] = password
	}
	addTLS(outbound, node, false)
	return outbound, nil
}

func outboundFromNode(node map[string]any) (map[string]any, error) {
	switch strings.ToLower(stringValue(node, "type")) {
	case "vless":
		return vlessOutbound(node)
	case "vmess":
		return vmessOutbound(node)
	case "trojan":
		return trojanOutbound(node)
	case "ss", "shadowsocks":
		return shadowsocksOutbound(node)
	case "hysteria2":
		return hysteria2Outbound(node)
	case "hysteria":
		return hysteriaOutbound(node)
	case "tuic":
		return tuicOutbound(node)
	case "anytls":
		return anyTLSOutbound(node)
	case "socks", "socks5":
		return socksOutbound(node)
	case "http", "naive":
		return httpOutbound(node)
	default:
		return nil, fmt.Errorf("unsupported target type for sing-box outbound: %s", stringValue(node, "type"))
	}
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: relay-parser '<proxy-url>'")
		os.Exit(2)
	}

	node, err := proxyparser.Parse(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	outbound, err := outboundFromNode(node)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(outbound); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
