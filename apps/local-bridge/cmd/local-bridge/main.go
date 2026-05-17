package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/kizzle/onlymacs/apps/local-bridge/internal/httpapi"
)

func main() {
	addr := os.Getenv("ONLYMACS_BRIDGE_ADDR")
	if addr == "" {
		addr = "127.0.0.1:4318"
	}
	runtimeStatePath := os.Getenv("ONLYMACS_RUNTIME_STATE_PATH")
	if runtimeStatePath == "" {
		if stateDir := os.Getenv("ONLYMACS_STATE_DIR"); stateDir != "" {
			runtimeStatePath = filepath.Join(stateDir, "runtime.json")
		}
	}

	server := &http.Server{
		Addr:              addr,
		Handler:           httpapi.NewMuxWithConfig(httpapi.ConfigFromEnv(runtimeStatePath)),
		ReadHeaderTimeout: httpapi.LocalBridgeReadHeaderTimeout,
		IdleTimeout:       httpapi.LocalBridgeIdleTimeout,
	}

	log.Printf("onlymacs local bridge listening on %s", strings.Map(func(r rune) rune { // #nosec G706 -- addr is stripped of CR/LF before logging.
		if r == '\r' || r == '\n' {
			return -1
		}
		return r
	}, addr))
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
