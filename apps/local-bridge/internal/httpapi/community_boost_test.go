package httpapi

import "testing"

func TestEstimateCommunityBoostStartsNewUsersAtStandard(t *testing.T) {
	summary := estimateCommunityBoost(0, localShareStatus{})

	if summary.Level != 3 || summary.Label != "Steady" {
		t.Fatalf("expected new users to start at Steady (3/5), got %d %q", summary.Level, summary.Label)
	}
	if summary.PrimaryTrait != "Fresh Face" {
		t.Fatalf("expected fresh face trait, got %q", summary.PrimaryTrait)
	}
}

func TestEstimateCommunityBoostRewardsReliableBackboneHosts(t *testing.T) {
	summary := estimateCommunityBoost(25_000, localShareStatus{
		Published:              true,
		Slots:                  slots{Free: 1, Total: 1},
		PublishedModels:        []model{{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B"}},
		ServedSessions:         140,
		ServedStreamSessions:   120,
		UploadedTokensEstimate: 1_600_000,
	})

	if summary.Level < 4 {
		t.Fatalf("expected backbone mac host to reach Hot or Headliner, got %d %q", summary.Level, summary.Label)
	}
	if summary.PrimaryTrait != "Backbone Mac" {
		t.Fatalf("expected backbone mac trait, got %q", summary.PrimaryTrait)
	}
}

func TestEstimateCommunityBoostGivesPremiumHostsAProvisionalFloor(t *testing.T) {
	summary := estimateCommunityBoost(0, localShareStatus{
		Published: true,
		Slots:     slots{Free: 4, Total: 4},
		PublishedModels: []model{
			{ID: "llama-4-maverick:400b", Name: "Llama 4 Maverick"},
			{ID: "qwen3:235b-a22b", Name: "Qwen3 235B A22B"},
		},
	})

	if summary.Level < 4 {
		t.Fatalf("expected new heavy hitter hosts to start at Hot or better, got %d %q", summary.Level, summary.Label)
	}
	if summary.PrimaryTrait != "Heavy Hitter" {
		t.Fatalf("expected heavy hitter trait, got %q", summary.PrimaryTrait)
	}
}

func TestBuildUsageSummaryPreservesMutedSmallSwarmContext(t *testing.T) {
	summary := buildUsageSummary(requestMetricsSnapshot{}, localShareStatus{}, &memberSummaryResponse{
		CommunityBoost: coordinatorCommunityBoostSummary{
			Level:        3,
			Label:        "Small Swarm",
			MetricLabel:  "Swarm Context",
			PrimaryTrait: "Friend Group",
			Traits:       []string{"Friend Group"},
			Detail:       "Small private swarm fairness is muted for now.",
		},
	})

	if summary.CommunityBoost.MetricLabel != "Swarm Context" {
		t.Fatalf("expected muted metric label to survive bridge mapping, got %q", summary.CommunityBoost.MetricLabel)
	}
	if summary.CommunityBoost.Label != "Small Swarm" {
		t.Fatalf("expected small-swarm label to survive bridge mapping, got %q", summary.CommunityBoost.Label)
	}
}
