package httpapi

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

const defaultPublicSwarmID = "swarm-public"

type runtimeConfig struct {
	Mode          string `json:"mode"`
	ActiveSwarmID string `json:"active_swarm_id"`
}

func (c *runtimeConfig) UnmarshalJSON(data []byte) error {
	type rawRuntimeConfig struct {
		Mode             string `json:"mode"`
		ActiveSwarmID    string `json:"active_swarm_id"`
		LegacyActivePool string `json:"active_pool_id"`
	}
	var raw rawRuntimeConfig
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	c.Mode = raw.Mode
	c.ActiveSwarmID = bridgeCanonicalSwarmID(firstNonEmpty(raw.ActiveSwarmID, raw.LegacyActivePool))
	return nil
}

type runtimeStore struct {
	mu     sync.RWMutex
	path   string
	config runtimeConfig
}

func newRuntimeStore(path string) *runtimeStore {
	store := &runtimeStore{
		path: strings.TrimSpace(path),
		config: runtimeConfig{
			Mode:          "both",
			ActiveSwarmID: defaultPublicSwarmID,
		},
	}
	store.load()
	return store
}

func (s *runtimeStore) Get() runtimeConfig {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.config
}

func (s *runtimeStore) Set(next runtimeConfig) runtimeConfig {
	s.mu.Lock()
	defer s.mu.Unlock()

	if next.Mode == "" {
		next.Mode = s.config.Mode
	}
	if next.ActiveSwarmID == "" {
		next.ActiveSwarmID = defaultPublicSwarmID
	}
	s.config = next
	s.persistLocked()
	return s.config
}

func (s *runtimeStore) load() {
	if s.path == "" {
		return
	}
	body, err := os.ReadFile(s.path) // #nosec G304 -- runtime state path is local app configuration, not remote input.
	if err != nil {
		return
	}
	var stored runtimeConfig
	if err := json.Unmarshal(body, &stored); err != nil {
		return
	}
	if stored.Mode == "" {
		stored.Mode = s.config.Mode
	}
	if stored.ActiveSwarmID == "" {
		stored.ActiveSwarmID = s.config.ActiveSwarmID
	}
	s.config = stored
}

func (s *runtimeStore) persistLocked() {
	if s.path == "" {
		return
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return
	}
	body, err := json.MarshalIndent(s.config, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(s.path, body, 0o600)
}

func bridgeCanonicalSwarmID(id string) string {
	id = strings.TrimSpace(id)
	switch {
	case id == "pool-public":
		return defaultPublicSwarmID
	case strings.HasPrefix(id, "pool-"):
		return "swarm-" + strings.TrimPrefix(id, "pool-")
	default:
		return id
	}
}

func modeAllowsUse(mode string) bool {
	return mode == "use" || mode == "both"
}

func modeAllowsShare(mode string) bool {
	return mode == "share" || mode == "both"
}
