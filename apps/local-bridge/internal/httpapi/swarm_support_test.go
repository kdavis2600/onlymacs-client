package httpapi

import (
	"reflect"
	"testing"
)

func TestProviderPreferenceIDsForRouteMergesRemoteFirstAndRequestedLists(t *testing.T) {
	localProviderID := localProviderIDForRoute()

	avoidProviderIDs, excludeProviderIDs := providerPreferenceIDsForRoute(
		routeScopeSwarm,
		true,
		false,
		[]string{" provider-old ", "provider-old", ""},
		[]string{"provider-bad", localProviderID},
	)

	if want := []string{"provider-old"}; !reflect.DeepEqual(avoidProviderIDs, want) {
		t.Fatalf("expected requested avoid providers %v, got %v", want, avoidProviderIDs)
	}
	if want := []string{localProviderID, "provider-bad"}; !reflect.DeepEqual(excludeProviderIDs, want) {
		t.Fatalf("expected route and requested exclude providers %v, got %v", want, excludeProviderIDs)
	}
}

func TestProviderPreferenceIDsForRouteMergesSoftRemoteAndRequestedLists(t *testing.T) {
	localProviderID := localProviderIDForRoute()

	avoidProviderIDs, excludeProviderIDs := providerPreferenceIDsForRoute(
		routeScopeSwarm,
		false,
		true,
		[]string{"provider-old"},
		[]string{" provider-bad "},
	)

	if want := []string{localProviderID, "provider-old"}; !reflect.DeepEqual(avoidProviderIDs, want) {
		t.Fatalf("expected route and requested avoid providers %v, got %v", want, avoidProviderIDs)
	}
	if want := []string{"provider-bad"}; !reflect.DeepEqual(excludeProviderIDs, want) {
		t.Fatalf("expected requested exclude providers %v, got %v", want, excludeProviderIDs)
	}
}

func TestProviderPreferenceIDsForRouteKeepsExplicitListsOutsideSwarm(t *testing.T) {
	avoidProviderIDs, excludeProviderIDs := providerPreferenceIDsForRoute(
		routeScopeTrustedOnly,
		true,
		true,
		[]string{"provider-old"},
		[]string{"provider-bad"},
	)

	if want := []string{"provider-old"}; !reflect.DeepEqual(avoidProviderIDs, want) {
		t.Fatalf("expected explicit avoid providers %v, got %v", want, avoidProviderIDs)
	}
	if want := []string{"provider-bad"}; !reflect.DeepEqual(excludeProviderIDs, want) {
		t.Fatalf("expected explicit exclude providers %v, got %v", want, excludeProviderIDs)
	}
}
