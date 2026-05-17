package httpapi

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"time"
)

var (
	providerRelayHeartbeatInterval       = 30 * time.Second
	providerRelayReconcileTimeout        = 5 * time.Second
	providerRelayActiveReconcileInterval = 5 * time.Second
	providerRelayHandledPollInterval     = 250 * time.Millisecond
	providerRelayIdlePollInterval        = 30 * time.Second
	providerRelayErrorPollInterval       = 30 * time.Second
	providerRelayRateLimitPollInterval   = 60 * time.Second
)

func (s *service) startProviderRelayWorker() {
	go func() {
		for {
			handled, err := s.pollProviderRelayOnce(context.Background())
			switch {
			case err != nil:
				time.Sleep(providerRelaySleepAfterError(err))
			case handled:
				time.Sleep(providerRelayHandledPollInterval)
			default:
				time.Sleep(providerRelayIdlePollInterval)
			}
		}
	}()
}

func providerRelaySleepAfterError(err error) time.Duration {
	if err == nil {
		return providerRelayIdlePollInterval
	}
	var httpErr coordinatorHTTPError
	if asCoordinatorHTTPError(err, &httpErr) && httpErr.StatusCode == http.StatusTooManyRequests {
		return providerRelayRateLimitPollInterval
	}
	if strings.Contains(strings.ToLower(err.Error()), "error code: 1027") {
		return providerRelayRateLimitPollInterval
	}
	return providerRelayErrorPollInterval
}

func (s *service) pollProviderRelayOnce(ctx context.Context) (bool, error) {
	runtime := s.runtime.Get()
	if !modeAllowsShare(runtime.Mode) {
		return false, nil
	}

	providerID, _ := localProviderIdentity()
	job, found, err := s.coordinator.pollRelay(ctx, providerID)
	if err != nil {
		var httpErr coordinatorHTTPError
		if asCoordinatorHTTPError(err, &httpErr) && httpErr.StatusCode == http.StatusNotFound {
			return false, nil
		}
		return false, err
	}
	if !found {
		return false, nil
	}

	s.shareMetrics.beginActiveSession(job.ResolvedModel)
	s.reconcileSharePublicationBestEffort(providerRelayReconcileTimeout)
	activeSessionOpen := true
	finishActiveSession := func() {
		if activeSessionOpen {
			s.shareMetrics.endActiveSession(job.ResolvedModel)
			activeSessionOpen = false
		}
	}
	defer func() {
		finishActiveSession()
		s.reconcileSharePublicationBestEffort(providerRelayReconcileTimeout)
	}()

	var req chatCompletionsRequest
	if err := json.Unmarshal(job.Request, &req); err != nil {
		completeErr := s.coordinator.completeRelay(ctx, providerRelayCompleteRequest{
			JobID:       job.JobID,
			ProviderID:  providerID,
			LeaseToken:  job.LeaseToken,
			StatusCode:  http.StatusBadRequest,
			ContentType: "application/json",
			BodyBase64:  encodeRelayJSONError("INVALID_RELAY_REQUEST", err.Error()),
		})
		return true, completeErr
	}

	if job.Stream {
		return true, s.streamProviderRelay(ctx, job, req)
	}

	var (
		statusCode int
		headers    http.Header
		body       []byte
	)
	if s.cfg.CannedChat {
		providerID, providerName := localProviderIdentity()
		selected := preflightProvider{
			ID:   providerID,
			Name: providerName,
		}
		var contentType string
		body, contentType = buildCannedChatCompletionBody(selected, job.ResolvedModel, job.SessionID)
		statusCode = http.StatusOK
		headers = http.Header{"Content-Type": []string{contentType}}
	} else {
		statusCode, headers, body, err = s.inference.executeChatCompletions(ctx, req, job.ResolvedModel)
		if err != nil {
			statusCode = http.StatusBadGateway
			body = []byte(`{"error":{"code":"INFERENCE_UNAVAILABLE","message":"remote provider inference failed"}}`)
			headers = http.Header{"Content-Type": []string{"application/json"}}
		}
	}

	contentType := headers.Get("Content-Type")
	if contentType == "" {
		contentType = "application/json"
	}

	if err := s.coordinator.completeRelay(ctx, providerRelayCompleteRequest{
		JobID:       job.JobID,
		ProviderID:  providerID,
		LeaseToken:  job.LeaseToken,
		StatusCode:  statusCode,
		ContentType: contentType,
		BodyBase64:  base64.StdEncoding.EncodeToString(body),
	}); err != nil {
		return true, err
	}
	if statusCode < http.StatusBadRequest {
		s.shareMetrics.recordCompletion(job.ResolvedModel, estimateResponseTokensFromBody(contentType, body), false)
	} else {
		s.shareMetrics.recordFailure(job.ResolvedModel)
	}

	return true, nil
}

func (s *service) streamProviderRelay(ctx context.Context, job providerRelayPollResponse, req chatCompletionsRequest) error {
	providerID, providerName := localProviderIdentity()
	var contentType string
	var statusCode int
	totalTokens := 0
	lastActiveReconcile := time.Now()
	reconcileIfDue := func() {
		if time.Since(lastActiveReconcile) < providerRelayActiveReconcileInterval {
			return
		}
		lastActiveReconcile = time.Now()
		s.reconcileSharePublicationSoon()
	}

	if s.cfg.CannedChat {
		selected := preflightProvider{
			ID:   providerID,
			Name: providerName,
		}
		for _, chunk := range cannedChatStreamChunks(selected, job.ResolvedModel, job.SessionID) {
			contentType = "text/event-stream"
			statusCode = http.StatusOK
			totalTokens += estimateResponseTokensFromBody(contentType, chunk)
			s.shareMetrics.recordStreamChunk(contentType, chunk)
			reconcileIfDue()
			if err := s.coordinator.pushRelayChunk(ctx, providerRelayChunkRequest{
				JobID:       job.JobID,
				ProviderID:  providerID,
				LeaseToken:  job.LeaseToken,
				StatusCode:  statusCode,
				ContentType: contentType,
				BodyBase64:  base64.StdEncoding.EncodeToString(chunk),
			}); err != nil {
				return err
			}
		}
	} else {
		relayCtx, cancelRelay := context.WithCancel(ctx)
		defer cancelRelay()
		stopHeartbeat := s.startProviderRelayStreamHeartbeatWithCancel(relayCtx, job, cancelRelay)
		defer stopHeartbeat()
		err := s.inference.streamChatCompletions(relayCtx, req, job.ResolvedModel, func(nextStatus int, headers http.Header, chunk []byte) error {
			statusCode = nextStatus
			contentType = headers.Get("Content-Type")
			if contentType == "" {
				contentType = "text/event-stream"
			}
			totalTokens += estimateResponseTokensFromBody(contentType, chunk)
			s.shareMetrics.recordStreamChunk(contentType, chunk)
			reconcileIfDue()
			return s.coordinator.pushRelayChunk(relayCtx, providerRelayChunkRequest{
				JobID:       job.JobID,
				ProviderID:  providerID,
				LeaseToken:  job.LeaseToken,
				StatusCode:  statusCode,
				ContentType: contentType,
				BodyBase64:  base64.StdEncoding.EncodeToString(chunk),
			})
		})
		if err != nil {
			if completeErr := s.coordinator.completeRelay(ctx, providerRelayCompleteRequest{
				JobID:       job.JobID,
				ProviderID:  providerID,
				LeaseToken:  job.LeaseToken,
				StatusCode:  http.StatusBadGateway,
				ContentType: "application/json",
				BodyBase64:  encodeRelayJSONError("INFERENCE_UNAVAILABLE", "remote provider inference failed"),
			}); completeErr != nil && !isRelayJobGone(completeErr) {
				return completeErr
			}
			s.shareMetrics.recordFailure(job.ResolvedModel)
			return nil
		}
	}

	if contentType == "" {
		contentType = "text/event-stream"
	}
	if statusCode == 0 {
		statusCode = http.StatusOK
	}

	if err := s.coordinator.completeRelay(ctx, providerRelayCompleteRequest{
		JobID:       job.JobID,
		ProviderID:  providerID,
		LeaseToken:  job.LeaseToken,
		StatusCode:  statusCode,
		ContentType: contentType,
	}); err != nil {
		if isRelayJobGone(err) {
			s.shareMetrics.recordFailure(job.ResolvedModel)
			return nil
		}
		return err
	}
	if statusCode < http.StatusBadRequest {
		s.shareMetrics.recordCompletion(job.ResolvedModel, totalTokens, true)
	} else {
		s.shareMetrics.recordFailure(job.ResolvedModel)
	}
	return nil
}

func (s *service) reconcileSharePublicationSoon() {
	go func() {
		s.reconcileSharePublicationBestEffort(providerRelayReconcileTimeout)
	}()
}

func (s *service) reconcileSharePublicationBestEffort(timeout time.Duration) {
	if timeout <= 0 {
		timeout = providerRelayReconcileTimeout
	}
	reconcileCtx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	_ = s.reconcileSharePublication(reconcileCtx)
}

func (s *service) startProviderRelayStreamHeartbeat(ctx context.Context, job providerRelayPollResponse) func() {
	return s.startProviderRelayStreamHeartbeatWithCancel(ctx, job, nil)
}

func (s *service) startProviderRelayStreamHeartbeatWithCancel(ctx context.Context, job providerRelayPollResponse, cancelRelay context.CancelFunc) func() {
	interval := providerRelayHeartbeatInterval
	if interval <= 0 {
		return func() {}
	}
	providerID, _ := localProviderIdentity()

	done := make(chan struct{})
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-done:
				return
			case <-ticker.C:
				err := s.coordinator.pushRelayChunk(ctx, providerRelayChunkRequest{
					JobID:       job.JobID,
					ProviderID:  providerID,
					LeaseToken:  job.LeaseToken,
					StatusCode:  http.StatusOK,
					ContentType: "text/event-stream",
					BodyBase64:  base64.StdEncoding.EncodeToString([]byte(": onlymacs heartbeat\n\n")),
				})
				if err != nil {
					if cancelRelay != nil {
						cancelRelay()
					}
					return
				}
			}
		}
	}()

	var stopped bool
	return func() {
		if stopped {
			return
		}
		stopped = true
		close(done)
	}
}

func isRelayJobGone(err error) bool {
	var httpErr coordinatorHTTPError
	return asCoordinatorHTTPError(err, &httpErr) && httpErr.StatusCode == http.StatusNotFound
}

func encodeRelayJSONError(code string, message string) string {
	payload, _ := json.Marshal(map[string]any{
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	})
	return base64.StdEncoding.EncodeToString(payload)
}
