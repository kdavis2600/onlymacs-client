package httpapi

import (
	"testing"
	"time"
)

func TestRollingThroughputEstimatesRecentTokensPerSecond(t *testing.T) {
	var throughput rollingThroughput
	now := time.Date(2026, time.April, 22, 12, 0, 0, 0, time.UTC)

	throughput.recordTokens(1_000, now.Add(-4*time.Second))
	throughput.recordTokens(500, now.Add(-2*time.Second))

	rate := throughput.recentTokensPerSecond(now)
	if rate <= 0 {
		t.Fatalf("expected positive recent token rate, got %f", rate)
	}
	if rate < 300 || rate > 400 {
		t.Fatalf("expected recent token rate to stay in expected range, got %f", rate)
	}
}

func TestRollingThroughputIgnoresOldSamples(t *testing.T) {
	var throughput rollingThroughput
	now := time.Date(2026, time.April, 22, 12, 0, 0, 0, time.UTC)

	throughput.recordTokens(2_000, now.Add(-20*time.Second))

	if rate := throughput.recentTokensPerSecond(now); rate != 0 {
		t.Fatalf("expected old samples to decay out of the recent window, got %f", rate)
	}
}
