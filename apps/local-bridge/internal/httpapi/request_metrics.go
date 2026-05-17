package httpapi

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type requestMetricsSnapshot struct {
	CompletedRequests        int        `json:"completed_requests"`
	CompletedStreamRequests  int        `json:"completed_stream_requests,omitempty"`
	FailedRequests           int        `json:"failed_requests,omitempty"`
	TokensSavedEstimate      int        `json:"tokens_saved_estimate"`
	DownloadedTokensEstimate int        `json:"downloaded_tokens_estimate"`
	RecentDownloadedTokensPS float64    `json:"recent_downloaded_tokens_per_second,omitempty"`
	LastCompletedModel       string     `json:"last_completed_model,omitempty"`
	LastCompletedAt          *time.Time `json:"last_completed_at,omitempty"`
}

type requestMetricsStore struct {
	mu              sync.RWMutex
	path            string
	snapshot        requestMetricsSnapshot
	recentDownloads rollingThroughput
}

func newRequestMetricsStore() *requestMetricsStore {
	store := &requestMetricsStore{
		path: requestMetricsPath(),
	}
	store.load()
	return store
}

func (s *requestMetricsStore) snapshotValue() requestMetricsSnapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()
	copy := s.snapshot
	copy.RecentDownloadedTokensPS = s.recentDownloads.recentTokensPerSecond(time.Now().UTC())
	return copy
}

func (s *requestMetricsStore) recordCompletion(modelID string, requestTokens int, responseTokens int, responseBytes int, streamed bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if requestTokens < 0 {
		requestTokens = 0
	}
	if responseTokens < 0 {
		responseTokens = 0
	}

	s.snapshot.CompletedRequests++
	if streamed {
		s.snapshot.CompletedStreamRequests++
	}
	s.snapshot.TokensSavedEstimate += requestTokens + responseTokens
	s.snapshot.DownloadedTokensEstimate += responseTokens
	s.snapshot.LastCompletedModel = modelID
	now := time.Now().UTC()
	s.snapshot.LastCompletedAt = &now
	s.persistLocked()
}

func (s *requestMetricsStore) recordFailure(modelID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.snapshot.FailedRequests++
	s.persistLocked()
}

func (s *requestMetricsStore) recordStreamChunk(contentType string, body []byte) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.recentDownloads.recordTokens(estimateResponseTokensFromBody(contentType, body), time.Now().UTC())
}

func (s *requestMetricsStore) load() {
	if s.path == "" {
		return
	}
	data, err := os.ReadFile(s.path) // #nosec G304 -- metrics path is local app configuration, not remote input.
	if err != nil {
		return
	}
	var snapshot requestMetricsSnapshot
	if json.Unmarshal(data, &snapshot) == nil {
		s.snapshot = snapshot
	}
}

func (s *requestMetricsStore) persistLocked() {
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

func requestMetricsPath() string {
	if override := strings.TrimSpace(os.Getenv("ONLYMACS_REQUEST_METRICS_PATH")); override != "" {
		return override
	}
	if strings.HasSuffix(filepath.Base(os.Args[0]), ".test") {
		return ""
	}
	configDir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(configDir, "OnlyMacs", "request-metrics-"+localNodeID()+".json")
}

func estimateTokensFromText(text string) int {
	return estimateTokensFromByteCount(len(text))
}

func estimateTokensFromByteCount(byteCount int) int {
	if byteCount <= 0 {
		return 0
	}
	tokens := byteCount / 4
	if tokens == 0 {
		return 1
	}
	return tokens
}

func estimateTokensFromResponseBytes(responseBytes int) int {
	return estimateTokensFromByteCount(responseBytes)
}

func estimateRequesterTokensFromMessages(messages []chatMessage) int {
	if len(messages) == 0 {
		return 0
	}
	totalBytes := 0
	for _, message := range messages {
		totalBytes += len(message.Content)
	}
	return estimateTokensFromByteCount(totalBytes)
}

func estimateRequesterTokensFromRequest(req chatCompletionsRequest) int {
	totalBytes := 0
	for _, message := range req.Messages {
		totalBytes += len(message.Content)
	}
	totalBytes += estimateOnlyMacsArtifactBytes(req.OnlyMacsArtifact)
	return estimateTokensFromByteCount(totalBytes)
}

func estimateResponseTokensFromBody(contentType string, body []byte) int {
	if isChatCompletionStreamBody(contentType, body) {
		output := parseChatCompletionStreamText(body)
		return estimateTokensFromText(output)
	}
	if output := parseChatCompletionText(body); output != "" {
		return estimateTokensFromText(output)
	}
	return estimateTokensFromResponseBytes(len(body))
}

func isChatCompletionStreamBody(contentType string, body []byte) bool {
	if strings.Contains(strings.ToLower(strings.TrimSpace(contentType)), "text/event-stream") {
		return true
	}
	for _, line := range strings.Split(string(body), "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "data:") {
			return true
		}
	}
	return false
}

func parseChatCompletionStreamText(body []byte) string {
	if len(body) == 0 {
		return ""
	}

	lines := strings.Split(string(body), "\n")
	parts := make([]string, 0)
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		payload := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if payload == "" || payload == "[DONE]" {
			continue
		}
		if output := parseChatCompletionText([]byte(payload)); output != "" {
			parts = append(parts, output)
		}
	}
	return strings.Join(parts, "")
}

func parseChatCompletionText(body []byte) string {
	if len(body) == 0 {
		return ""
	}

	type generatedFields struct {
		Content          json.RawMessage `json:"content"`
		Reasoning        json.RawMessage `json:"reasoning"`
		ReasoningContent json.RawMessage `json:"reasoning_content"`
		Thinking         json.RawMessage `json:"thinking"`
	}
	var payload struct {
		Choices []struct {
			Message  generatedFields `json:"message"`
			Delta    generatedFields `json:"delta"`
			Text     json.RawMessage `json:"text"`
			Logprobs json.RawMessage `json:"logprobs"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return ""
	}

	parts := make([]string, 0, len(payload.Choices))
	for _, choice := range payload.Choices {
		for _, value := range []string{
			rawGeneratedText(choice.Message.Reasoning),
			rawGeneratedText(choice.Message.ReasoningContent),
			rawGeneratedText(choice.Message.Thinking),
			rawGeneratedText(choice.Message.Content),
			rawGeneratedText(choice.Delta.Reasoning),
			rawGeneratedText(choice.Delta.ReasoningContent),
			rawGeneratedText(choice.Delta.Thinking),
			rawGeneratedText(choice.Delta.Content),
			rawGeneratedText(choice.Text),
		} {
			if value != "" {
				parts = append(parts, value)
			}
		}
	}
	return strings.Join(parts, "")
}

func rawGeneratedText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var value string
	if err := json.Unmarshal(raw, &value); err == nil {
		return value
	}
	var parts []struct {
		Text    json.RawMessage `json:"text"`
		Content json.RawMessage `json:"content"`
	}
	if err := json.Unmarshal(raw, &parts); err == nil {
		var builder strings.Builder
		for _, part := range parts {
			builder.WriteString(rawGeneratedText(part.Text))
			builder.WriteString(rawGeneratedText(part.Content))
		}
		return builder.String()
	}
	return ""
}
