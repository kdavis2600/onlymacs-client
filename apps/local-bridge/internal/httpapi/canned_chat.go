package httpapi

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

func cannedChatCompletionContent(selected preflightProvider, resolvedModel string) string {
	return fmt.Sprintf("OnlyMacs mock relay via %s for %s", selected.Name, resolvedModel)
}

func buildCannedChatCompletionBody(selected preflightProvider, resolvedModel string, sessionID string) ([]byte, string) {
	if delay := cannedChatDelay(); delay > 0 {
		time.Sleep(delay)
	}

	payload := map[string]any{
		"id":     sessionID,
		"object": "chat.completion",
		"choices": []map[string]any{
			{
				"index": 0,
				"message": map[string]any{
					"role":    "assistant",
					"content": cannedChatCompletionContent(selected, resolvedModel),
				},
				"finish_reason": "stop",
			},
		},
	}
	body, err := json.Marshal(payload)
	if err != nil {
		fallback := fmt.Sprintf(`{"id":%q,"object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":%q},"finish_reason":"stop"}]}`, sessionID, cannedChatCompletionContent(selected, resolvedModel))
		return []byte(fallback), "application/json"
	}
	return body, "application/json"
}

func writeCannedChatStream(w http.ResponseWriter, selected preflightProvider, resolvedModel string, sessionID string) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	for _, payload := range cannedChatStreamChunks(selected, resolvedModel, sessionID) {
		if delay := cannedChatDelay(); delay > 0 {
			time.Sleep(delay / 2)
		}
		fmt.Fprintf(w, "data: %s\n\n", payload)
		flusher.Flush()
	}

	fmt.Fprint(w, "data: [DONE]\n\n")
	flusher.Flush()
}

func cannedChatStreamChunks(selected preflightProvider, resolvedModel string, sessionID string) [][]byte {
	events := []map[string]any{
		{
			"id":     sessionID,
			"object": "chat.completion.chunk",
			"choices": []map[string]any{
				{
					"index": 0,
					"delta": map[string]any{
						"role":    "assistant",
						"content": "OnlyMacs ",
					},
				},
			},
		},
		{
			"id":     sessionID,
			"object": "chat.completion.chunk",
			"choices": []map[string]any{
				{
					"index": 0,
					"delta": map[string]any{
						"content": strings.TrimPrefix(cannedChatCompletionContent(selected, resolvedModel), "OnlyMacs "),
					},
				},
			},
		},
	}

	chunks := make([][]byte, 0, len(events))
	for _, event := range events {
		payload, err := json.Marshal(event)
		if err != nil {
			fallback := fmt.Sprintf(`{"id":%q,"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":%q}}]}`, sessionID, cannedChatCompletionContent(selected, resolvedModel))
			chunks = append(chunks, []byte(fallback))
			continue
		}
		chunks = append(chunks, payload)
	}
	return chunks
}

func cannedChatDelay() time.Duration {
	raw := strings.TrimSpace(os.Getenv("ONLYMACS_CANNED_CHAT_DELAY_MS"))
	if raw == "" {
		return 0
	}
	delayMS, err := strconv.Atoi(raw)
	if err != nil || delayMS <= 0 {
		return 0
	}
	return time.Duration(delayMS) * time.Millisecond
}
