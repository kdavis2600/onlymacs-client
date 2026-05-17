package httpapi

import "time"

const recentTokenRateWindow = 10 * time.Second

type throughputSample struct {
	recordedAt time.Time
	tokenCount int
}

type rollingThroughput struct {
	samples []throughputSample
}

func (r *rollingThroughput) recordTokens(tokenCount int, recordedAt time.Time) {
	if tokenCount <= 0 {
		return
	}
	r.samples = append(r.samples, throughputSample{
		recordedAt: recordedAt,
		tokenCount: tokenCount,
	})
	r.prune(recordedAt)
}

func (r *rollingThroughput) recentTokensPerSecond(now time.Time) float64 {
	if len(r.samples) == 0 {
		return 0
	}

	cutoff := now.Add(-recentTokenRateWindow)
	totalTokens := 0
	earliest := time.Time{}

	for _, sample := range r.samples {
		if sample.recordedAt.Before(cutoff) {
			continue
		}
		totalTokens += sample.tokenCount
		if earliest.IsZero() || sample.recordedAt.Before(earliest) {
			earliest = sample.recordedAt
		}
	}

	if totalTokens <= 0 || earliest.IsZero() {
		return 0
	}

	elapsed := now.Sub(earliest).Seconds()
	if elapsed < 1 {
		elapsed = 1
	}
	return float64(totalTokens) / elapsed
}

func (r *rollingThroughput) prune(now time.Time) {
	if len(r.samples) == 0 {
		return
	}

	cutoff := now.Add(-recentTokenRateWindow)
	keepFrom := 0
	for keepFrom < len(r.samples) && r.samples[keepFrom].recordedAt.Before(cutoff) {
		keepFrom++
	}
	if keepFrom == 0 {
		return
	}
	r.samples = append([]throughputSample(nil), r.samples[keepFrom:]...)
}
