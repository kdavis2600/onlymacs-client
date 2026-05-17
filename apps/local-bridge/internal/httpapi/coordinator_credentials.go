package httpapi

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

type coordinatorCredentialStore struct {
	mu    sync.RWMutex
	path  string
	state coordinatorCredentialState
}

type coordinatorCredentialState struct {
	Requester map[string]string `json:"requester_tokens,omitempty"`
	Provider  map[string]string `json:"provider_tokens,omitempty"`
	Device    map[string]string `json:"device_tokens,omitempty"`
}

func newCoordinatorCredentialStore(runtimeStatePath string) *coordinatorCredentialStore {
	store := &coordinatorCredentialStore{
		path: coordinatorCredentialPath(runtimeStatePath),
		state: coordinatorCredentialState{
			Requester: make(map[string]string),
			Provider:  make(map[string]string),
			Device:    make(map[string]string),
		},
	}
	store.load()
	return store
}

func coordinatorCredentialPath(runtimeStatePath string) string {
	runtimeStatePath = strings.TrimSpace(runtimeStatePath)
	if runtimeStatePath == "" {
		return ""
	}
	ext := filepath.Ext(runtimeStatePath)
	if ext == "" {
		return runtimeStatePath + ".credentials.json"
	}
	return strings.TrimSuffix(runtimeStatePath, ext) + ".credentials.json"
}

func (s *coordinatorCredentialStore) remember(credentials coordinatorCredentials) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state.Requester == nil {
		s.state.Requester = make(map[string]string)
	}
	if s.state.Provider == nil {
		s.state.Provider = make(map[string]string)
	}
	if s.state.Device == nil {
		s.state.Device = make(map[string]string)
	}
	if token := credentials.Requester; token != nil && strings.TrimSpace(token.Token) != "" {
		s.state.Requester[requesterCredentialKey(token.SwarmID, token.MemberID)] = strings.TrimSpace(token.Token)
	}
	if token := credentials.Provider; token != nil && strings.TrimSpace(token.Token) != "" {
		s.state.Provider[strings.TrimSpace(token.ProviderID)] = strings.TrimSpace(token.Token)
	}
	if token := credentials.Device; token != nil && strings.TrimSpace(token.Token) != "" {
		s.state.Device[requesterCredentialKey(token.SwarmID, token.MemberID)] = strings.TrimSpace(token.Token)
	}
	s.persistLocked()
}

func (s *coordinatorCredentialStore) rememberToken(token coordinatorTokenResponse) {
	if s == nil || strings.TrimSpace(token.Token) == "" {
		return
	}
	s.remember(coordinatorCredentials{
		Requester: requesterTokenPointer(token),
		Provider:  providerTokenPointer(token),
		Device:    deviceTokenPointer(token),
	})
}

func (s *coordinatorCredentialStore) requesterToken(swarmID string, memberID string) string {
	if s == nil {
		return ""
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return strings.TrimSpace(s.state.Requester[requesterCredentialKey(swarmID, memberID)])
}

func (s *coordinatorCredentialStore) forgetRequesterToken(swarmID string, memberID string) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state.Requester != nil {
		delete(s.state.Requester, requesterCredentialKey(swarmID, memberID))
	}
	s.persistLocked()
}

func (s *coordinatorCredentialStore) firstRequesterToken() string {
	if s == nil {
		return ""
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	keys := make([]string, 0, len(s.state.Requester))
	for key := range s.state.Requester {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if token := strings.TrimSpace(s.state.Requester[key]); token != "" {
			return token
		}
	}
	return ""
}

func (s *coordinatorCredentialStore) providerToken(providerID string) string {
	if s == nil {
		return ""
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return strings.TrimSpace(s.state.Provider[strings.TrimSpace(providerID)])
}

func (s *coordinatorCredentialStore) forgetProviderToken(providerID string) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state.Provider != nil {
		delete(s.state.Provider, strings.TrimSpace(providerID))
	}
	s.persistLocked()
}

func (s *coordinatorCredentialStore) firstProviderToken() string {
	if s == nil {
		return ""
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, token := range s.state.Provider {
		if strings.TrimSpace(token) != "" {
			return strings.TrimSpace(token)
		}
	}
	return ""
}

func requesterCredentialKey(swarmID string, memberID string) string {
	return strings.TrimSpace(swarmID) + "\x00" + strings.TrimSpace(memberID)
}

func requesterTokenPointer(token coordinatorTokenResponse) *coordinatorTokenResponse {
	if token.Scope != "requester" {
		return nil
	}
	return &token
}

func providerTokenPointer(token coordinatorTokenResponse) *coordinatorTokenResponse {
	if token.Scope != "provider" {
		return nil
	}
	return &token
}

func deviceTokenPointer(token coordinatorTokenResponse) *coordinatorTokenResponse {
	if token.Scope != "device" {
		return nil
	}
	return &token
}

func (s *coordinatorCredentialStore) load() {
	if s == nil || s.path == "" {
		return
	}
	body, err := os.ReadFile(s.path)
	if err != nil {
		return
	}
	var state coordinatorCredentialState
	if err := json.Unmarshal(body, &state); err != nil {
		return
	}
	if state.Requester == nil {
		state.Requester = make(map[string]string)
	}
	if state.Provider == nil {
		state.Provider = make(map[string]string)
	}
	if state.Device == nil {
		state.Device = make(map[string]string)
	}
	s.state = state
}

func (s *coordinatorCredentialStore) persistLocked() {
	if s == nil || s.path == "" {
		return
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return
	}
	body, err := json.MarshalIndent(s.state, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(s.path, body, 0o600)
}
