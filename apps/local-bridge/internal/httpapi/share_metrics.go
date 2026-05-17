package httpapi

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type shareMetricsSnapshot struct {
	ServedSessions         int        `json:"served_sessions"`
	ServedStreamSessions   int        `json:"served_stream_sessions"`
	FailedSessions         int        `json:"failed_sessions"`
	UploadedTokensEstimate int        `json:"uploaded_tokens_estimate"`
	RecentUploadedTokensPS float64    `json:"recent_uploaded_tokens_per_second,omitempty"`
	LastServedModel        string     `json:"last_served_model,omitempty"`
	LastServedAt           *time.Time `json:"last_served_at,omitempty"`
}

type shareMetricsStore struct {
	mu             sync.RWMutex
	path           string
	snapshot       shareMetricsSnapshot
	recentUploads  rollingThroughput
	activeSessions int
	activeModels   map[string]int
}

func newShareMetricsStore() *shareMetricsStore {
	store := &shareMetricsStore{
		path: shareMetricsPath(),
	}
	store.load()
	return store
}

func (s *shareMetricsStore) snapshotValue() shareMetricsSnapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()
	copy := s.snapshot
	copy.RecentUploadedTokensPS = s.recentUploads.recentTokensPerSecond(time.Now().UTC())
	return copy
}

func (s *shareMetricsStore) recordCompletion(modelID string, responseTokens int, streamed bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if responseTokens < 0 {
		responseTokens = 0
	}
	s.snapshot.ServedSessions++
	if streamed {
		s.snapshot.ServedStreamSessions++
	}
	s.snapshot.UploadedTokensEstimate += responseTokens
	s.snapshot.LastServedModel = modelID
	now := time.Now().UTC()
	s.snapshot.LastServedAt = &now
	s.persistLocked()
}

func (s *shareMetricsStore) recordFailure(modelID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.snapshot.FailedSessions++
	s.snapshot.LastServedModel = modelID
	now := time.Now().UTC()
	s.snapshot.LastServedAt = &now
	s.persistLocked()
}

func (s *shareMetricsStore) recordStreamChunk(contentType string, body []byte) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.recentUploads.recordTokens(estimateResponseTokensFromBody(contentType, body), time.Now().UTC())
}

func (s *shareMetricsStore) beginActiveSession(modelID ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.activeSessions++
	if len(modelID) == 0 {
		return
	}
	normalized := strings.TrimSpace(modelID[0])
	if normalized == "" {
		return
	}
	if s.activeModels == nil {
		s.activeModels = make(map[string]int)
	}
	s.activeModels[normalized]++
}

func (s *shareMetricsStore) endActiveSession(modelID ...string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.activeSessions > 0 {
		s.activeSessions--
	}
	if len(modelID) == 0 || s.activeModels == nil {
		return
	}
	normalized := strings.TrimSpace(modelID[0])
	if normalized == "" {
		return
	}
	if s.activeModels[normalized] <= 1 {
		delete(s.activeModels, normalized)
		return
	}
	s.activeModels[normalized]--
}

func (s *shareMetricsStore) activeSessionCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.activeSessions
}

func (s *shareMetricsStore) activeModel() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if len(s.activeModels) == 0 {
		return ""
	}
	selected := ""
	selectedCount := 0
	for modelID, count := range s.activeModels {
		if count > selectedCount || (count == selectedCount && (selected == "" || modelID < selected)) {
			selected = modelID
			selectedCount = count
		}
	}
	return selected
}

func (s *shareMetricsStore) load() {
	if s.path == "" {
		return
	}
	data, err := os.ReadFile(s.path) // #nosec G304 -- metrics path is local app configuration, not remote input.
	if err != nil {
		return
	}
	var snapshot shareMetricsSnapshot
	if json.Unmarshal(data, &snapshot) == nil {
		s.snapshot = snapshot
	}
}

func (s *shareMetricsStore) persistLocked() {
	if s.path == "" {
		return
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return
	}
	data, err := json.MarshalIndent(s.snapshot, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(s.path, data, 0o600)
}

func shareMetricsPath() string {
	if override := strings.TrimSpace(os.Getenv("ONLYMACS_SHARE_METRICS_PATH")); override != "" {
		return override
	}
	if strings.HasSuffix(filepath.Base(os.Args[0]), ".test") {
		return ""
	}
	configDir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(configDir, "OnlyMacs", "share-metrics-"+localNodeID()+".json")
}
