package httpapi

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode"
)

const localIdentitySchemaVersion = 1

var (
	localIdentityMu     sync.Mutex
	cachedLocalIdentity *localIdentity
)

type localIdentity struct {
	SchemaVersion int       `json:"schema_version"`
	MemberName    string    `json:"member_name"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type localIdentityResponse struct {
	MemberID     string `json:"member_id"`
	MemberName   string `json:"member_name"`
	ProviderID   string `json:"provider_id"`
	ProviderName string `json:"provider_name"`
}

type updateLocalIdentityRequest struct {
	MemberName string `json:"member_name"`
}

func (s *service) identityHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, currentLocalIdentityResponse())
	case http.MethodPost:
		var req updateLocalIdentityRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_JSON", err.Error()))
			return
		}
		name, err := normalizeMemberDisplayName(req.MemberName)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_MEMBER_NAME", err.Error()))
			return
		}
		if err := saveLocalIdentityName(name); err != nil {
			writeJSON(w, http.StatusInternalServerError, invalidRequest("IDENTITY_SAVE_FAILED", err.Error()))
			return
		}
		if err := s.refreshLocalMembership(r.Context()); err != nil {
			writeJSON(w, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error()))
			return
		}
		writeJSON(w, http.StatusOK, currentLocalIdentityResponse())
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "identity endpoint supports GET and POST",
			},
		})
	}
}

func currentLocalIdentityResponse() localIdentityResponse {
	memberID, memberName := localMemberIdentity()
	providerID, providerName := localProviderIdentity()
	return localIdentityResponse{
		MemberID:     memberID,
		MemberName:   memberName,
		ProviderID:   providerID,
		ProviderName: providerName,
	}
}

func localIdentityName() string {
	if override := strings.TrimSpace(os.Getenv("ONLYMACS_MEMBER_NAME")); override != "" {
		if name, err := normalizeMemberDisplayName(override); err == nil {
			return name
		}
	}
	identity, err := readOrCreateLocalIdentity()
	if err != nil || strings.TrimSpace(identity.MemberName) == "" {
		return defaultLocalMemberName()
	}
	return identity.MemberName
}

func readOrCreateLocalIdentity() (localIdentity, error) {
	localIdentityMu.Lock()
	defer localIdentityMu.Unlock()

	if cachedLocalIdentity != nil {
		return *cachedLocalIdentity, nil
	}

	path, err := localIdentityPath()
	if err != nil {
		identity := newDefaultLocalIdentity()
		cachedLocalIdentity = &identity
		return identity, err
	}

	if data, readErr := os.ReadFile(path); readErr == nil { // #nosec G304 -- identity path is derived from the user config directory.
		var identity localIdentity
		if json.Unmarshal(data, &identity) == nil {
			if name, normalizeErr := normalizeMemberDisplayName(identity.MemberName); normalizeErr == nil {
				identity.MemberName = name
				if identity.SchemaVersion == 0 {
					identity.SchemaVersion = localIdentitySchemaVersion
				}
				cachedLocalIdentity = &identity
				return identity, nil
			}
		}
	}

	identity := newDefaultLocalIdentity()
	if writeErr := writeLocalIdentity(path, identity); writeErr != nil {
		cachedLocalIdentity = &identity
		return identity, writeErr
	}
	cachedLocalIdentity = &identity
	return identity, nil
}

func saveLocalIdentityName(name string) error {
	normalized, err := normalizeMemberDisplayName(name)
	if err != nil {
		return err
	}
	path, err := localIdentityPath()
	if err != nil {
		return err
	}

	localIdentityMu.Lock()
	defer localIdentityMu.Unlock()

	now := time.Now().UTC()
	identity := localIdentity{
		SchemaVersion: localIdentitySchemaVersion,
		MemberName:    normalized,
		CreatedAt:     now,
		UpdatedAt:     now,
	}
	if cachedLocalIdentity != nil {
		identity.CreatedAt = cachedLocalIdentity.CreatedAt
		if identity.CreatedAt.IsZero() {
			identity.CreatedAt = now
		}
	}
	if err := writeLocalIdentity(path, identity); err != nil {
		return err
	}
	cachedLocalIdentity = &identity
	return nil
}

func writeLocalIdentity(path string, identity localIdentity) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(identity, "", "  ")
	if err != nil {
		return err
	}
	tmpPath := path + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmpPath, path)
}

func newDefaultLocalIdentity() localIdentity {
	now := time.Now().UTC()
	return localIdentity{
		SchemaVersion: localIdentitySchemaVersion,
		MemberName:    defaultLocalMemberName(),
		CreatedAt:     now,
		UpdatedAt:     now,
	}
}

func defaultLocalMemberName() string {
	if name := strings.TrimSpace(os.Getenv("ONLYMACS_DEFAULT_MEMBER_NAME")); name != "" {
		if normalized, err := normalizeMemberDisplayName(name); err == nil {
			return normalized
		}
	}
	if name := macOSComputerName(); name != "" {
		return name
	}
	words := []string{
		"Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel",
		"India", "Juliet", "Kilo", "Lima", "Mike", "November", "Oscar", "Papa",
		"Quebec", "Romeo", "Sierra", "Tango", "Uniform", "Victor", "Whiskey", "Xray",
		"Yankee", "Zulu",
	}
	sum := sha256.Sum256([]byte(localNodeID()))
	left := int(sum[0]) % len(words)
	right := int(sum[1]) % len(words)
	if right == left {
		right = (right + 7) % len(words)
	}
	return words[left] + "-" + words[right]
}

func macOSComputerName() string {
	output, err := exec.Command("/usr/sbin/scutil", "--get", "ComputerName").Output()
	if err == nil {
		if name, normalizeErr := normalizeMemberDisplayName(string(output)); normalizeErr == nil {
			return name
		}
	}
	if hostname, hostnameErr := os.Hostname(); hostnameErr == nil {
		hostname = strings.TrimSuffix(hostname, ".local")
		hostname = strings.ReplaceAll(hostname, "-", " ")
		if name, normalizeErr := normalizeMemberDisplayName(hostname); normalizeErr == nil {
			return name
		}
	}
	return ""
}

func normalizeMemberDisplayName(value string) (string, error) {
	name := strings.TrimSpace(value)
	if name == "" {
		return "", fmt.Errorf("member_name is required")
	}
	if len([]rune(name)) > 80 {
		return "", fmt.Errorf("member_name must be 80 characters or fewer")
	}
	for _, r := range name {
		if unicode.IsControl(r) {
			return "", fmt.Errorf("member_name cannot contain control characters")
		}
	}
	return name, nil
}

func localIdentityPath() (string, error) {
	if override := strings.TrimSpace(os.Getenv("ONLYMACS_IDENTITY_PATH")); override != "" {
		return override, nil
	}
	if strings.HasSuffix(filepath.Base(os.Args[0]), ".test") {
		return filepath.Join(os.TempDir(), "onlymacs-local-identity-"+localNodeID()+".json"), nil
	}
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(configDir, "OnlyMacs", "local-identity-"+localNodeID()+".json"), nil
}

func resetLocalIdentityCacheForTest() {
	localIdentityMu.Lock()
	defer localIdentityMu.Unlock()
	cachedLocalIdentity = nil
}
