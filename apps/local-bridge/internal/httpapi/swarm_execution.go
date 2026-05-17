package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

const swarmOutputPreviewLimit = 1200

type swarmExecutionStore struct {
	mu      sync.Mutex
	cancels map[string]context.CancelFunc
}

type swarmReservationExecutionResult struct {
	Index         int
	ReservationID string
	ProviderID    string
	ProviderName  string
	Output        string
	ResponseBytes int
	Err           error
	Status        string
}

func newSwarmExecutionStore() *swarmExecutionStore {
	return &swarmExecutionStore{
		cancels: make(map[string]context.CancelFunc),
	}
}

func (s *swarmExecutionStore) start(sessionID string, cancel context.CancelFunc) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.cancels[sessionID]; exists {
		return false
	}
	s.cancels[sessionID] = cancel
	return true
}

func (s *swarmExecutionStore) cancel(sessionID string) bool {
	s.mu.Lock()
	cancel, exists := s.cancels[sessionID]
	if exists {
		delete(s.cancels, sessionID)
	}
	s.mu.Unlock()
	if exists {
		cancel()
	}
	return exists
}

func (s *swarmExecutionStore) clear(sessionID string) {
	s.mu.Lock()
	delete(s.cancels, sessionID)
	s.mu.Unlock()
}

func (s *service) maybeStartSwarmExecution(session swarmSessionSummary) {
	if s.cfg.DisableSwarmExecution || session.Status != "running" || len(session.Reservations) == 0 {
		return
	}

	ctx, cancel := context.WithCancel(context.Background())
	if !s.swarmRuns.start(session.ID, cancel) {
		cancel()
		return
	}

	go s.runSwarmExecution(ctx, session)
}

func (s *service) runSwarmExecution(ctx context.Context, session swarmSessionSummary) {
	defer s.swarmRuns.clear(session.ID)

	req, err := buildSwarmChatRequest(session)
	if err != nil {
		if ctx.Err() == nil {
			s.finalizeSwarmExecution(session.ID, nil, err)
		}
		return
	}

	results := s.executeSwarmReservations(ctx, session, req)
	if ctx.Err() != nil {
		return
	}

	s.finalizeSwarmExecution(session.ID, results, nil)
}

func buildSwarmChatRequest(session swarmSessionSummary) (chatCompletionsRequest, error) {
	messages := append([]chatMessage(nil), session.Messages...)
	if len(messages) == 0 && strings.TrimSpace(session.Prompt) != "" {
		messages = []chatMessage{{
			Role:    "user",
			Content: session.Prompt,
		}}
	}
	if len(messages) == 0 {
		return chatCompletionsRequest{}, fmt.Errorf("OnlyMacs could not execute this swarm because no prompt or messages were stored")
	}
	return chatCompletionsRequest{
		Model:            session.ResolvedModel,
		Stream:           false,
		OnlyMacsArtifact: session.OnlyMacsArtifact,
		Messages:         messages,
	}, nil
}

func (s *service) executeSwarmReservations(ctx context.Context, session swarmSessionSummary, req chatCompletionsRequest) []swarmReservationExecutionResult {
	results := make([]swarmReservationExecutionResult, 0, len(session.Reservations))
	resultCh := make(chan swarmReservationExecutionResult, len(session.Reservations))

	var wg sync.WaitGroup
	for idx, reservation := range session.Reservations {
		wg.Add(1)
		go func(index int, reservation swarmSessionReservation) {
			defer wg.Done()
			resultCh <- s.executeSwarmReservation(ctx, session, req, index, reservation)
		}(idx, reservation)
	}

	wg.Wait()
	close(resultCh)

	for result := range resultCh {
		results = append(results, result)
	}
	sort.Slice(results, func(i, j int) bool {
		return results[i].Index < results[j].Index
	})
	return results
}

func (s *service) executeSwarmReservation(ctx context.Context, session swarmSessionSummary, req chatCompletionsRequest, index int, reservation swarmSessionReservation) swarmReservationExecutionResult {
	result := swarmReservationExecutionResult{
		Index:         index,
		ReservationID: reservation.ReservationID,
		ProviderID:    reservation.ProviderID,
		ProviderName:  reservation.ProviderName,
		Status:        "failed",
	}

	selected := preflightProvider{
		ID:   reservation.ProviderID,
		Name: defaultValue(strings.TrimSpace(reservation.ProviderName), "This Mac"),
	}

	localProviderID, _ := localProviderIdentity()
	swarmID, requesterMemberID := s.swarmRequesterContext(session)
	switch {
	case reservation.ProviderID != localProviderID:
		relayResp, err := s.coordinator.executeRelay(
			ctx,
			reservation.ReservationID,
			reservation.ProviderID,
			session.ResolvedModel,
			swarmID,
			requesterMemberID,
			req,
		)
		if err != nil {
			result.Err = err
			return result
		}
		body, err := decodeRelayBody(relayResp.BodyBase64)
		if err != nil {
			result.Err = err
			return result
		}
		statusCode := relayResp.StatusCode
		if statusCode <= 0 {
			statusCode = http.StatusOK
		}
		output, err := extractSwarmExecutionOutput(statusCode, relayResp.ContentType, body)
		if err != nil {
			result.Err = err
			return result
		}
		result.Output = output
		result.ResponseBytes = len(body)
	case s.cfg.CannedChat:
		body, contentType := buildCannedChatCompletionBody(selected, session.ResolvedModel, reservation.ReservationID)
		output, err := extractSwarmExecutionOutput(http.StatusOK, contentType, body)
		if err != nil {
			result.Err = err
			return result
		}
		result.Output = output
		result.ResponseBytes = len(body)
	default:
		statusCode, headers, body, err := s.inference.executeChatCompletions(ctx, req, session.ResolvedModel)
		if err != nil {
			result.Err = err
			return result
		}
		contentType := ""
		if headers != nil {
			contentType = headers.Get("Content-Type")
		}
		output, err := extractSwarmExecutionOutput(statusCode, contentType, body)
		if err != nil {
			result.Err = err
			return result
		}
		result.Output = output
		result.ResponseBytes = len(body)
	}

	result.Status = "completed"
	return result
}

func (s *service) swarmRequesterContext(session swarmSessionSummary) (string, string) {
	swarmID := strings.TrimSpace(session.SwarmID)
	if swarmID == "" {
		swarmID = strings.TrimSpace(s.runtime.Get().ActiveSwarmID)
	}
	memberID, _ := localMemberIdentity()
	return swarmID, memberID
}

func (s *service) finalizeSwarmExecution(sessionID string, results []swarmReservationExecutionResult, executionErr error) {
	session, ok := s.swarms.get(sessionID)
	if !ok || session.Status != "running" {
		return
	}

	if len(session.Reservations) > 0 {
		s.releaseSwarmReservations(session)
	}
	for idx := range session.Reservations {
		session.Reservations[idx].Status = "released"
	}

	session.QueueRemainder = 0
	session.QueuePosition = 0
	session.ETASeconds = 0
	session.QueueReason = ""

	if executionErr != nil {
		for idx := range session.Reservations {
			session.Reservations[idx].Status = "failed"
		}
		message := strings.TrimSpace(executionErr.Error())
		session.Status = "failed"
		session.Checkpoint = &swarmCheckpoint{
			Status:        "failed",
			Partial:       false,
			OutputBytes:   0,
			OutputPreview: truncateSwarmOutputPreview(message),
			LastError:     message,
			UpdatedAt:     time.Now().UTC(),
		}
		session = s.swarms.update(session)
		s.requestMetrics.recordFailure(session.ResolvedModel)
		return
	}

	successes := make([]swarmReservationExecutionResult, 0, len(results))
	failures := make([]swarmReservationExecutionResult, 0, len(results))
	statusByReservation := make(map[string]string, len(results))
	for _, result := range results {
		statusByReservation[result.ReservationID] = result.Status
		if result.Err != nil {
			failures = append(failures, result)
		} else {
			successes = append(successes, result)
		}
	}
	for idx := range session.Reservations {
		if status, ok := statusByReservation[session.Reservations[idx].ReservationID]; ok {
			session.Reservations[idx].Status = status
		}
	}

	output := combineSwarmOutputs(successes)
	checkpoint := &swarmCheckpoint{
		UpdatedAt: time.Now().UTC(),
	}
	requestTokens := session.Context.EstimatedTokens * len(successes)
	responseTokens := 0
	for _, result := range successes {
		responseTokens += estimateTokensFromText(result.Output)
	}
	actualSavedTokens := requestTokens + responseTokens

	if len(successes) == 0 {
		errorSummary := summarizeSwarmErrors(failures)
		checkpoint.Status = "failed"
		checkpoint.Partial = false
		checkpoint.OutputBytes = 0
		checkpoint.OutputPreview = truncateSwarmOutputPreview(errorSummary)
		checkpoint.LastError = errorSummary
		session.Status = "failed"
	} else {
		checkpoint.Status = "completed"
		checkpoint.Partial = len(failures) > 0
		checkpoint.OutputBytes = len(output)
		checkpoint.OutputPreview = truncateSwarmOutputPreview(output)
		session.SavedTokensEstimate = actualSavedTokens
		if len(failures) > 0 {
			checkpoint.LastError = summarizeSwarmErrors(failures)
			session.Warnings = append(session.Warnings, fmt.Sprintf("%d of %d swarm worker%s failed; OnlyMacs kept the successful output.", len(failures), len(results), pluralSuffix(len(results))))
		}
		session.Status = "completed"
	}

	session.Warnings = uniqueStrings(session.Warnings)
	session.Checkpoint = checkpoint
	localProviderID, _ := localProviderIdentity()
	localProviderUpdated := false
	for _, result := range successes {
		if result.ProviderID != localProviderID {
			continue
		}
		s.shareMetrics.recordCompletion(session.ResolvedModel, estimateTokensFromText(result.Output), false)
		localProviderUpdated = true
	}
	for _, result := range failures {
		if result.ProviderID != localProviderID {
			continue
		}
		s.shareMetrics.recordFailure(session.ResolvedModel)
		localProviderUpdated = true
	}
	if localProviderUpdated {
		_ = s.reconcileSharePublication(context.Background())
	}
	if len(successes) > 0 {
		responseBytes := 0
		if checkpoint != nil {
			responseBytes = checkpoint.OutputBytes
		}
		s.requestMetrics.recordCompletion(session.ResolvedModel, requestTokens, responseTokens, responseBytes, false)
	} else {
		s.requestMetrics.recordFailure(session.ResolvedModel)
	}
	session = s.swarms.update(session)
}

func combineSwarmOutputs(results []swarmReservationExecutionResult) string {
	if len(results) == 0 {
		return ""
	}
	if len(results) == 1 {
		output := strings.TrimSpace(results[0].Output)
		if output == "" {
			return "Swarm execution completed without textual output."
		}
		return output
	}

	parts := make([]string, 0, len(results))
	for _, result := range results {
		output := strings.TrimSpace(result.Output)
		if output == "" {
			continue
		}
		provider := defaultValue(strings.TrimSpace(result.ProviderName), defaultValue(strings.TrimSpace(result.ProviderID), "unknown provider"))
		parts = append(parts, fmt.Sprintf("[%s]\n%s", provider, output))
	}
	if len(parts) == 0 {
		return "Swarm execution completed without textual output."
	}
	return strings.Join(parts, "\n\n")
}

func summarizeSwarmErrors(results []swarmReservationExecutionResult) string {
	if len(results) == 0 {
		return "Swarm execution failed without an error message."
	}
	parts := make([]string, 0, len(results))
	for _, result := range results {
		if result.Err == nil {
			continue
		}
		provider := defaultValue(strings.TrimSpace(result.ProviderName), defaultValue(strings.TrimSpace(result.ProviderID), "unknown provider"))
		parts = append(parts, fmt.Sprintf("%s: %s", provider, strings.TrimSpace(result.Err.Error())))
	}
	if len(parts) == 0 {
		return "Swarm execution failed without an error message."
	}
	return strings.Join(parts, " | ")
}

func truncateSwarmOutputPreview(output string) string {
	output = strings.TrimSpace(output)
	if output == "" {
		return ""
	}
	if len(output) <= swarmOutputPreviewLimit {
		return output
	}
	return strings.TrimSpace(output[:swarmOutputPreviewLimit-3]) + "..."
}

func extractSwarmExecutionOutput(statusCode int, contentType string, body []byte) (string, error) {
	trimmedBody := strings.TrimSpace(string(body))
	if statusCode >= http.StatusBadRequest {
		if trimmedBody == "" {
			trimmedBody = fmt.Sprintf("upstream returned status %d", statusCode)
		}
		return "", fmt.Errorf("%s", trimmedBody)
	}

	if output := parseChatCompletionText(body); output != "" {
		return output, nil
	}
	if trimmedBody != "" && !strings.Contains(strings.ToLower(contentType), "json") {
		return trimmedBody, nil
	}
	if trimmedBody != "" {
		return trimmedBody, nil
	}
	return "", fmt.Errorf("OnlyMacs received an empty response body from the selected provider")
}
