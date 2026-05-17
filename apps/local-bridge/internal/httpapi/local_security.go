package httpapi

import (
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	defaultBridgeRequestBodyLimit = 1 * 1024 * 1024
	chatBridgeRequestBodyLimit    = 80 * 1024 * 1024

	LocalBridgeReadHeaderTimeout = 10 * time.Second
	LocalBridgeIdleTimeout       = 2 * time.Minute
)

func localBridgeSecurityMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !localBridgeRemoteAddrAllowed(r.RemoteAddr) {
			writeJSON(w, http.StatusForbidden, map[string]any{
				"error": map[string]any{
					"code":    "LOCAL_BRIDGE_REMOTE_BLOCKED",
					"message": "OnlyMacs local bridge only accepts loopback clients",
				},
			})
			return
		}
		if !localBridgeHostAllowed(r.Host, r.RemoteAddr) {
			writeJSON(w, http.StatusForbidden, map[string]any{
				"error": map[string]any{
					"code":    "LOCAL_BRIDGE_HOST_BLOCKED",
					"message": "OnlyMacs local bridge only accepts localhost requests",
				},
			})
			return
		}
		if !localBridgeBrowserContextAllowed(r) {
			writeJSON(w, http.StatusForbidden, map[string]any{
				"error": map[string]any{
					"code":    "LOCAL_BRIDGE_BROWSER_CONTEXT_BLOCKED",
					"message": "OnlyMacs local bridge rejected a cross-site browser request",
				},
			})
			return
		}
		if localBridgeRequestMayHaveBody(r.Method) {
			r.Body = http.MaxBytesReader(w, r.Body, localBridgeRequestBodyLimit(r.URL.Path))
		}
		next.ServeHTTP(w, r)
	})
}

func localBridgeRemoteAddrAllowed(remoteAddr string) bool {
	remoteAddr = strings.TrimSpace(remoteAddr)
	if remoteAddr == "" || localBridgeHTTPTestRemoteAddr(remoteAddr) {
		return true
	}
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		host = remoteAddr
	}
	host = strings.Trim(host, "[]")
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func localBridgeHTTPTestRemoteAddr(remoteAddr string) bool {
	return strings.HasPrefix(strings.TrimSpace(remoteAddr), "192.0.2.1:")
}

func localBridgeRequestMayHaveBody(method string) bool {
	switch method {
	case http.MethodPost, http.MethodPut, http.MethodPatch:
		return true
	default:
		return false
	}
}

func localBridgeRequestBodyLimit(path string) int64 {
	if path == "/v1/chat/completions" {
		return chatBridgeRequestBodyLimit
	}
	return defaultBridgeRequestBodyLimit
}

func localBridgeHostAllowed(hostHeader string, remoteAddr string) bool {
	host := strings.TrimSpace(hostHeader)
	if host == "" {
		return true
	}
	return localBridgeHostNameAllowed(host)
}

func localBridgeHostNameAllowed(host string) bool {
	if parsedHost, _, err := net.SplitHostPort(host); err == nil {
		host = parsedHost
	}
	host = strings.Trim(host, "[]")
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func localBridgeBrowserContextAllowed(r *http.Request) bool {
	if site := strings.ToLower(strings.TrimSpace(r.Header.Get("Sec-Fetch-Site"))); site == "cross-site" {
		return false
	}
	origin := strings.TrimSpace(r.Header.Get("Origin"))
	if origin == "" {
		return true
	}
	parsed, err := url.Parse(origin)
	if err != nil {
		return false
	}
	return localBridgeHostNameAllowed(parsed.Host)
}
