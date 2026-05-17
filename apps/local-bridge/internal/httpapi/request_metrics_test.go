package httpapi

import (
	"strings"
	"testing"
)

func TestEstimateResponseTokensFromStreamingChatUsesDeltaText(t *testing.T) {
	body := []byte("data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\ndata: [DONE]\n")

	tokens := estimateResponseTokensFromBody("text/event-stream", body)
	protocolTokens := estimateTokensFromResponseBytes(len(body))
	textTokens := estimateTokensFromText("hello world")

	if tokens != textTokens {
		t.Fatalf("expected stream estimate to use decoded content tokens, got %d want %d", tokens, textTokens)
	}
	if tokens >= protocolTokens {
		t.Fatalf("expected decoded stream estimate %d to stay below protocol byte estimate %d", tokens, protocolTokens)
	}
}

func TestEstimateResponseTokensFromStreamingChatIncludesDeltaReasoning(t *testing.T) {
	body := []byte("data: {\"choices\":[{\"delta\":{\"reasoning\":\"think \",\"content\":\"done\"}}]}\n\ndata: [DONE]\n")

	tokens := estimateResponseTokensFromBody("text/event-stream", body)
	want := estimateTokensFromText("think done")

	if tokens != want {
		t.Fatalf("expected stream estimate to include reasoning and content, got %d want %d", tokens, want)
	}
}

func TestEstimateResponseTokensFromNonStreamingChatIncludesReasoning(t *testing.T) {
	body := []byte(`{"choices":[{"message":{"role":"assistant","reasoning":"hidden plan ","content":"final answer"}}]}`)

	tokens := estimateResponseTokensFromBody("application/json", body)
	want := estimateTokensFromText("hidden plan final answer")

	if tokens != want {
		t.Fatalf("expected non-stream estimate to include reasoning and content, got %d want %d", tokens, want)
	}
}

func TestEstimateResponseTokensFromStreamingChatDoesNotCountEnvelopeBytes(t *testing.T) {
	body := []byte("data: {\"id\":\"" + strings.Repeat("x", 2048) + "\",\"choices\":[{\"delta\":{}}]}\n\n")

	tokens := estimateResponseTokensFromBody("text/event-stream", body)

	if tokens != 0 {
		t.Fatalf("expected empty generated stream chunk to count as zero tokens, got %d", tokens)
	}
}

func TestRequestCompletionDoesNotCreateRecentRateForNonStreamingSample(t *testing.T) {
	store := &requestMetricsStore{}

	store.recordCompletion("qwen2.5-coder:32b", 100, 2_000, 8_000, false)

	if got := store.snapshotValue().RecentDownloadedTokensPS; got != 0 {
		t.Fatalf("expected non-streaming completion not to create recent token rate, got %f", got)
	}
}
