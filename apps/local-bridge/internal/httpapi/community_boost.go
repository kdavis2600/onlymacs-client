package httpapi

import "strings"

type communityBoostSummary struct {
	Level        int      `json:"level"`
	Label        string   `json:"label"`
	MetricLabel  string   `json:"metric_label,omitempty"`
	PrimaryTrait string   `json:"primary_trait,omitempty"`
	Traits       []string `json:"traits,omitempty"`
	Detail       string   `json:"detail,omitempty"`
}

type usageSummary struct {
	TokensSavedEstimate      int                   `json:"tokens_saved_estimate"`
	DownloadedTokensEstimate int                   `json:"downloaded_tokens_estimate"`
	UploadedTokensEstimate   int                   `json:"uploaded_tokens_estimate"`
	RecentRemoteTokensPS     float64               `json:"recent_remote_tokens_per_second,omitempty"`
	ActiveReservations       int                   `json:"active_reservations,omitempty"`
	ReservationCap           int                   `json:"reservation_cap,omitempty"`
	CommunityBoost           communityBoostSummary `json:"community_boost"`
}

func buildUsageSummary(requestMetrics requestMetricsSnapshot, share localShareStatus, memberSummary *memberSummaryResponse) usageSummary {
	downloaded := requestMetrics.DownloadedTokensEstimate
	uploaded := share.UploadedTokensEstimate
	boost := estimateCommunityBoost(downloaded, share)
	if memberSummary != nil {
		if memberSummary.UploadedTokensEstimate > uploaded {
			uploaded = memberSummary.UploadedTokensEstimate
		}
		boost = communityBoostSummary{
			Level:        memberSummary.CommunityBoost.Level,
			Label:        memberSummary.CommunityBoost.Label,
			MetricLabel:  memberSummary.CommunityBoost.MetricLabel,
			PrimaryTrait: memberSummary.CommunityBoost.PrimaryTrait,
			Traits:       memberSummary.CommunityBoost.Traits,
			Detail:       memberSummary.CommunityBoost.Detail,
		}
	}
	return usageSummary{
		TokensSavedEstimate:      requestMetrics.TokensSavedEstimate,
		DownloadedTokensEstimate: downloaded,
		UploadedTokensEstimate:   uploaded,
		RecentRemoteTokensPS:     requestMetrics.RecentDownloadedTokensPS,
		ActiveReservations:       memberReservationCount(memberSummary),
		ReservationCap:           memberReservationCap(memberSummary),
		CommunityBoost:           boost,
	}
}

func memberReservationCount(memberSummary *memberSummaryResponse) int {
	if memberSummary == nil {
		return 0
	}
	return memberSummary.ActiveReservations
}

func memberReservationCap(memberSummary *memberSummaryResponse) int {
	if memberSummary == nil {
		return 0
	}
	return memberSummary.ReservationCap
}

func estimateCommunityBoost(downloadedTokens int, share localShareStatus) communityBoostSummary {
	contribution := contributionScore(share)
	capability := capabilityScore(share)
	hasSharingSignals := share.Published || len(share.PublishedModels) > 0

	if contribution == 0 && capability == 0 && downloadedTokens == 0 && !hasSharingSignals {
		return communityBoostSummary{
			Level:        3,
			Label:        "Steady",
			MetricLabel:  "Community Boost",
			PrimaryTrait: "Fresh Face",
			Traits:       []string{"Fresh Face"},
			Detail:       "Fresh start. Share this Mac and your boost climbs when the rare slots get crowded.",
		}
	}

	high := maxBoostInt(contribution, capability)
	low := minBoostInt(contribution, capability)
	effective := ((high * 3) + low) / 4
	level, label := communityBand(effective)
	traits := communityTraits(contribution, capability, share)
	if len(traits) == 0 {
		if downloadedTokens > 0 {
			traits = []string{"In The Mix"}
		} else {
			traits = []string{"Warming Up"}
		}
	}

	return communityBoostSummary{
		Level:        level,
		Label:        label,
		MetricLabel:  "Community Boost",
		PrimaryTrait: traits[0],
		Traits:       traits,
		Detail:       communityDetail(downloadedTokens, contribution, capability, share, label),
	}
}

func contributionScore(share localShareStatus) int {
	score := 0
	switch {
	case share.UploadedTokensEstimate >= 1_000_000:
		score += 42
	case share.UploadedTokensEstimate >= 250_000:
		score += 32
	case share.UploadedTokensEstimate >= 50_000:
		score += 22
	case share.UploadedTokensEstimate > 0:
		score += 10
	}

	switch {
	case share.ServedSessions >= 100:
		score += 38
	case share.ServedSessions >= 25:
		score += 28
	case share.ServedSessions >= 10:
		score += 18
	case share.ServedSessions > 0:
		score += 8
	}

	switch {
	case share.ServedStreamSessions >= 25:
		score += 10
	case share.ServedStreamSessions > 0:
		score += 5
	}

	return minBoostInt(score, 95)
}

func capabilityScore(share localShareStatus) int {
	if !share.Published && len(share.PublishedModels) == 0 {
		return 0
	}

	bestModel := 0
	for _, model := range share.PublishedModels {
		bestModel = maxBoostInt(bestModel, modelCapabilityPoints(model.ID))
	}

	slotBonus := 0
	switch {
	case share.Slots.Total >= 4:
		slotBonus = 12
	case share.Slots.Total >= 2:
		slotBonus = 6
	case share.Slots.Total >= 1:
		slotBonus = 3
	}

	breadthBonus := 0
	switch {
	case len(share.PublishedModels) >= 5:
		breadthBonus = 12
	case len(share.PublishedModels) >= 3:
		breadthBonus = 8
	case len(share.PublishedModels) >= 2:
		breadthBonus = 4
	}

	return minBoostInt(bestModel+slotBonus+breadthBonus, 95)
}

func modelCapabilityPoints(modelID string) int {
	normalized := strings.ToLower(strings.TrimSpace(modelID))
	switch {
	case normalized == "":
		return 0
	case strings.Contains(normalized, "maverick"),
		strings.Contains(normalized, "405b"),
		strings.Contains(normalized, "400b"),
		strings.Contains(normalized, "235b"),
		strings.Contains(normalized, "220b"),
		strings.Contains(normalized, "671b"),
		strings.Contains(normalized, "a22b"):
		return 82
	case strings.Contains(normalized, "90b"),
		strings.Contains(normalized, "72b"),
		strings.Contains(normalized, "70b"),
		strings.Contains(normalized, "32b"),
		strings.Contains(normalized, "31b"):
		return 66
	case strings.Contains(normalized, "27b"),
		strings.Contains(normalized, "26b"),
		strings.Contains(normalized, "24b"),
		strings.Contains(normalized, "22b"),
		strings.Contains(normalized, "14b"):
		return 48
	case strings.Contains(normalized, "9b"),
		strings.Contains(normalized, "8b"),
		strings.Contains(normalized, "7b"):
		return 30
	case strings.Contains(normalized, "4b"),
		strings.Contains(normalized, "3b"),
		strings.Contains(normalized, "1.5b"):
		return 16
	default:
		return 12
	}
}

func communityBand(score int) (int, string) {
	switch {
	case score >= 85:
		return 5, "Headliner"
	case score >= 70:
		return 4, "Hot"
	case score >= 50:
		return 3, "Steady"
	case score >= 35:
		return 2, "Warming Up"
	default:
		return 1, "Cold"
	}
}

func communityTraits(contribution int, capability int, share localShareStatus) []string {
	traits := make([]string, 0, 3)
	if contribution >= 55 || share.ServedSessions >= 25 || share.UploadedTokensEstimate >= 250_000 {
		traits = append(traits, "Backbone Mac")
	}
	if capability >= 70 {
		traits = append(traits, "Heavy Hitter")
	}
	if len(share.PublishedModels) >= 3 {
		traits = append(traits, "Deep Bench")
	}
	return traits
}

func communityDetail(downloadedTokens int, contribution int, capability int, share localShareStatus, label string) string {
	switch {
	case capability >= 70 && contribution < 35:
		return "This Mac already has premium heat. A few real sessions and the boost climbs fast."
	case contribution >= 55 && capability < 70:
		return "This Mac keeps showing up. Leave it online and it starts winning more close calls when premium slots get tight."
	case share.UploadedTokensEstimate > downloadedTokens && share.UploadedTokensEstimate > 0:
		return "You are feeding the swarm more than you are draining it. That helps when the rare stuff gets crowded."
	case downloadedTokens > share.UploadedTokensEstimate && downloadedTokens > 0:
		return "You are leaning on the swarm more than you are feeding it right now. Share this Mac more often to climb the next tiebreak."
	case label == "Headliner":
		return "OnlyMacs treats this machine like a headliner when rare premium capacity gets crowded."
	default:
		return "Community Boost only breaks close calls. Owner priority, safety limits, and live capacity still run the show."
	}
}

func minBoostInt(a int, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxBoostInt(a int, b int) int {
	if a > b {
		return a
	}
	return b
}
