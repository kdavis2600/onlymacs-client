package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

type ollamaModelsResponse struct {
	Data []ollamaModel `json:"data"`
}

type ollamaModel struct {
	ID string `json:"id"`
}

type inferenceClient struct {
	baseURL    string
	httpClient *http.Client
}

func newInferenceClient(cfg Config) *inferenceClient {
	httpClient := cfg.InferenceHTTPClient
	if httpClient == nil {
		httpClient = defaultConfig().InferenceHTTPClient
	}

	baseURL := strings.TrimRight(strings.TrimSpace(cfg.OllamaURL), "/")
	if baseURL == "" {
		baseURL = strings.TrimRight(defaultConfig().OllamaURL, "/")
	}

	return &inferenceClient{
		baseURL:    baseURL,
		httpClient: httpClient,
	}
}

func (c *inferenceClient) executeChatCompletions(ctx context.Context, req chatCompletionsRequest, resolvedModel string) (int, http.Header, []byte, error) {
	if handled, statusCode, headers, body, err := maybeExecuteOnlyMacsToolWorkspace(ctx, req); handled {
		if err == nil {
			return statusCode, headers, body, nil
		}
	}
	if c.baseURL == "" {
		return 0, nil, nil, fmt.Errorf("inference backend URL is not configured")
	}

	preparedReq, cleanup, err := prepareOnlyMacsRequestForInference(req)
	if err != nil {
		return 0, nil, nil, err
	}
	defer cleanup()

	preparedReq.Model = resolvedModel
	body, err := json.Marshal(preparedReq)
	if err != nil {
		return 0, nil, nil, err
	}

	upstreamReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v1/chat/completions", bytes.NewReader(body))
	if err != nil {
		return 0, nil, nil, err
	}
	upstreamReq.Header.Set("Content-Type", "application/json")

	upstreamResp, err := c.httpClient.Do(upstreamReq)
	if err != nil {
		return 0, nil, nil, err
	}
	defer upstreamResp.Body.Close()

	respBody, err := io.ReadAll(upstreamResp.Body)
	if err != nil {
		return 0, nil, nil, err
	}

	return upstreamResp.StatusCode, upstreamResp.Header.Clone(), respBody, nil
}

func (c *inferenceClient) proxyChatCompletions(ctx context.Context, w http.ResponseWriter, req chatCompletionsRequest, resolvedModel string) error {
	if handled, statusCode, headers, body, err := maybeExecuteOnlyMacsToolWorkspace(ctx, req); handled {
		if err == nil {
			copyResponseHeader(w.Header(), headers, "Content-Type", "Cache-Control", "Connection")
			if statusCode == 0 {
				statusCode = http.StatusOK
			}
			w.WriteHeader(statusCode)
			if len(body) > 0 {
				_, _ = w.Write(body)
			}
			return nil
		}
	}
	if c.baseURL == "" {
		return fmt.Errorf("inference backend URL is not configured")
	}

	preparedReq, cleanup, err := prepareOnlyMacsRequestForInference(req)
	if err != nil {
		return err
	}
	defer cleanup()

	preparedReq.Model = resolvedModel
	body, err := json.Marshal(preparedReq)
	if err != nil {
		return err
	}

	upstreamReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v1/chat/completions", bytes.NewReader(body))
	if err != nil {
		return err
	}
	upstreamReq.Header.Set("Content-Type", "application/json")

	upstreamResp, err := c.httpClient.Do(upstreamReq)
	if err != nil {
		return err
	}
	defer upstreamResp.Body.Close()

	copyResponseHeader(w.Header(), upstreamResp.Header, "Content-Type", "Cache-Control", "Connection")
	w.WriteHeader(upstreamResp.StatusCode)

	flusher, _ := w.(http.Flusher)
	buffer := make([]byte, 32*1024)
	for {
		n, readErr := upstreamResp.Body.Read(buffer)
		if n > 0 {
			if _, writeErr := w.Write(buffer[:n]); writeErr != nil {
				return nil
			}
			if flusher != nil {
				flusher.Flush()
			}
		}

		if readErr == nil {
			continue
		}
		if readErr == io.EOF {
			return nil
		}
		return nil
	}
}

func (c *inferenceClient) streamChatCompletions(
	ctx context.Context,
	req chatCompletionsRequest,
	resolvedModel string,
	onChunk func(statusCode int, headers http.Header, chunk []byte) error,
) error {
	if handled, statusCode, _, body, err := maybeExecuteOnlyMacsToolWorkspace(ctx, req); handled {
		if err == nil {
			streamBody, streamErr := buildOnlyMacsChatCompletionStreamBody(extractOnlyMacsAssistantContent(body))
			if streamErr != nil {
				return streamErr
			}
			streamHeaders := http.Header{"Content-Type": []string{"text/event-stream"}}
			return onChunk(statusCode, streamHeaders, streamBody)
		}
	}
	if c.baseURL == "" {
		return fmt.Errorf("inference backend URL is not configured")
	}

	preparedReq, cleanup, err := prepareOnlyMacsRequestForInference(req)
	if err != nil {
		return err
	}
	defer cleanup()

	preparedReq.Model = resolvedModel
	body, err := json.Marshal(preparedReq)
	if err != nil {
		return err
	}

	upstreamReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v1/chat/completions", bytes.NewReader(body))
	if err != nil {
		return err
	}
	upstreamReq.Header.Set("Content-Type", "application/json")

	upstreamResp, err := c.httpClient.Do(upstreamReq)
	if err != nil {
		return err
	}
	defer upstreamResp.Body.Close()

	headers := upstreamResp.Header.Clone()
	buffer := make([]byte, 32*1024)
	for {
		n, readErr := upstreamResp.Body.Read(buffer)
		if n > 0 {
			if err := onChunk(upstreamResp.StatusCode, headers, append([]byte(nil), buffer[:n]...)); err != nil {
				return err
			}
		}

		if readErr == nil {
			continue
		}
		if readErr == io.EOF {
			return nil
		}
		return readErr
	}
}

func (c *inferenceClient) listModels(ctx context.Context) ([]model, error) {
	if c.baseURL == "" {
		return nil, fmt.Errorf("inference backend URL is not configured")
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/v1/models", nil)
	if err != nil {
		return nil, err
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("inference backend returned %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var payload ollamaModelsResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, err
	}

	models := make([]model, 0, len(payload.Data))
	for _, item := range payload.Data {
		modelID := strings.TrimSpace(item.ID)
		if modelID == "" {
			continue
		}
		models = append(models, model{
			ID:         modelID,
			Name:       humanizeModelName(modelID),
			SlotsFree:  1,
			SlotsTotal: 1,
		})
	}
	return models, nil
}

func copyResponseHeader(dst, src http.Header, keys ...string) {
	for _, key := range keys {
		values := src.Values(key)
		if len(values) == 0 {
			continue
		}
		for _, value := range values {
			dst.Add(key, value)
		}
	}
}

func humanizeModelName(modelID string) string {
	switch modelID {
	case "qwen2.5-coder:32b":
		return "Qwen2.5 Coder 32B"
	case "gemma4:26b":
		return "Gemma 4 26B"
	case "gemma4:31b":
		return "Gemma 4 31B"
	case "translategemma:27b":
		return "Translate Gemma 27B"
	default:
		return modelID
	}
}
