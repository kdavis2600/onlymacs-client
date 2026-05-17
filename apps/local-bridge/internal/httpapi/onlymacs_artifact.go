package httpapi

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

const (
	onlyMacsArtifactFileReady   = "ready"
	onlyMacsArtifactFileTrimmed = "trimmed"
	onlyMacsArtifactMaxFiles    = 5000
	onlyMacsArtifactMaxBytes    = 256 * 1024 * 1024
)

func prepareOnlyMacsRequestForInference(req chatCompletionsRequest) (chatCompletionsRequest, func(), error) {
	if req.OnlyMacsArtifact == nil {
		return req, func() {}, nil
	}

	rootDir, cleanup, err := stageOnlyMacsArtifact(req.OnlyMacsArtifact)
	if err != nil {
		return chatCompletionsRequest{}, cleanup, err
	}

	prepared := req
	prepared.OnlyMacsArtifact = nil
	prepared.Messages = appendOnlyMacsArtifactContext(req.Messages, renderOnlyMacsArtifactContext(req.OnlyMacsArtifact, rootDir))
	return prepared, cleanup, nil
}

func estimateOnlyMacsArtifactBytes(payload *onlyMacsArtifactPayload) int {
	if payload == nil {
		return 0
	}
	if payload.Manifest.TotalExportBytes > 0 {
		return payload.Manifest.TotalExportBytes
	}
	if payload.BundleBase64 == "" {
		return 0
	}
	return (len(payload.BundleBase64) * 3) / 4
}

func appendOnlyMacsArtifactContext(messages []chatMessage, artifactContext string) []chatMessage {
	if strings.TrimSpace(artifactContext) == "" {
		return append([]chatMessage(nil), messages...)
	}

	cloned := append([]chatMessage(nil), messages...)
	for idx := len(cloned) - 1; idx >= 0; idx-- {
		if strings.EqualFold(cloned[idx].Role, "user") {
			existing := strings.TrimSpace(cloned[idx].Content)
			if existing == "" {
				cloned[idx].Content = artifactContext
			} else {
				cloned[idx].Content = existing + "\n\n---\n\n" + artifactContext
			}
			return cloned
		}
	}

	return append(cloned, chatMessage{
		Role:    "user",
		Content: artifactContext,
	})
}

func stageOnlyMacsArtifact(payload *onlyMacsArtifactPayload) (string, func(), error) {
	bundleBase64 := strings.TrimSpace(payload.BundleBase64)
	if bundleBase64 == "" {
		return "", func() {}, fmt.Errorf("OnlyMacs artifact bundle is missing")
	}

	bundleData, err := base64.StdEncoding.DecodeString(bundleBase64)
	if err != nil {
		return "", func() {}, fmt.Errorf("OnlyMacs artifact bundle could not be decoded: %w", err)
	}

	if expected := strings.TrimSpace(payload.BundleSHA256); expected != "" {
		sum := sha256.Sum256(bundleData)
		actual := hex.EncodeToString(sum[:])
		if !strings.EqualFold(actual, expected) {
			return "", func() {}, fmt.Errorf("OnlyMacs artifact bundle failed checksum verification")
		}
	}

	tempDir, cleanup, err := onlyMacsArtifactStagingRoot(payload.Manifest)
	if err != nil {
		return "", func() {}, fmt.Errorf("OnlyMacs artifact bundle could not create staging workspace: %w", err)
	}

	rootDir, err := extractOnlyMacsArtifactBundle(bundleData, tempDir)
	if err != nil {
		cleanup()
		return "", func() {}, err
	}
	if err := prepareOnlyMacsStagedWorkspace(rootDir, payload.Manifest); err != nil {
		cleanup()
		return "", func() {}, err
	}
	if err := validateOnlyMacsArtifact(payload, rootDir); err != nil {
		cleanup()
		return "", func() {}, err
	}

	return rootDir, cleanup, nil
}

func onlyMacsArtifactStagingRoot(manifest onlyMacsArtifactManifest) (string, func(), error) {
	if strings.TrimSpace(manifest.Lease.ID) == "" {
		tempDir, err := os.MkdirTemp("", "onlymacs-artifact-*")
		if err != nil {
			return "", func() {}, err
		}
		return tempDir, func() {
			_ = os.RemoveAll(tempDir)
		}, nil
	}

	stateRoot, err := onlyMacsLeaseRoot()
	if err != nil {
		return "", func() {}, err
	}
	leaseRoot := filepath.Join(stateRoot, sanitizeOnlyMacsLeaseID(manifest.Lease.ID))
	workspaceRoot := filepath.Join(leaseRoot, "workspace")
	if err := os.RemoveAll(workspaceRoot); err != nil {
		return "", func() {}, err
	}
	if err := os.MkdirAll(leaseRoot, 0o700); err != nil {
		return "", func() {}, err
	}
	return leaseRoot, func() {}, nil
}

func prepareOnlyMacsStagedWorkspace(rootDir string, manifest onlyMacsArtifactManifest) error {
	if strings.TrimSpace(manifest.Lease.ID) != "" {
		if err := persistOnlyMacsLeaseMetadata(rootDir, manifest); err != nil {
			return err
		}
	}
	if strings.EqualFold(strings.TrimSpace(manifest.Workspace.Kind), "git_backed") {
		if err := ensureOnlyMacsGitWorkspace(rootDir, manifest); err != nil {
			return err
		}
	}
	return nil
}

func onlyMacsLeaseRoot() (string, error) {
	if stateDir := strings.TrimSpace(os.Getenv("ONLYMACS_STATE_DIR")); stateDir != "" {
		root := filepath.Join(stateDir, "bridge-leases")
		if err := os.MkdirAll(root, 0o700); err != nil { // #nosec G703 -- ONLYMACS_STATE_DIR is a local process configuration value.
			return "", err
		}
		return root, nil
	}
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		return "", err
	}
	root := filepath.Join(cacheDir, "onlymacs", "bridge-leases")
	if err := os.MkdirAll(root, 0o700); err != nil {
		return "", err
	}
	return root, nil
}

func sanitizeOnlyMacsLeaseID(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return "lease"
	}
	var builder strings.Builder
	for _, r := range value {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			builder.WriteRune(r)
		case r == '-', r == '_':
			builder.WriteRune(r)
		default:
			builder.WriteByte('-')
		}
	}
	return builder.String()
}

func persistOnlyMacsLeaseMetadata(rootDir string, manifest onlyMacsArtifactManifest) error {
	metadata := map[string]any{
		"lease_id":              manifest.Lease.ID,
		"lease_mode":            manifest.Lease.Mode,
		"round":                 manifest.Lease.Round,
		"max_rounds":            manifest.Lease.MaxRounds,
		"expires_at":            manifest.Lease.ExpiresAt,
		"workspace_fingerprint": manifest.WorkspaceFingerprint,
		"trust_tier":            manifest.TrustTier,
	}
	body, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(filepath.Dir(rootDir), "lease.json"), body, 0o600)
}

func ensureOnlyMacsGitWorkspace(rootDir string, manifest onlyMacsArtifactManifest) error {
	if _, err := os.Stat(filepath.Join(rootDir, ".git")); err == nil {
		return nil
	}

	if _, err := exec.LookPath("git"); err != nil {
		return fmt.Errorf("OnlyMacs could not prepare a git-backed workspace because git is not installed on this provider")
	}

	commands := [][]string{
		{"init", "-q"},
		{"config", "user.name", "OnlyMacs"},
		{"config", "user.email", "onlymacs@local.invalid"},
		{"add", "."},
		{"commit", "-q", "-m", "OnlyMacs staged baseline"},
	}
	for _, args := range commands {
		cmd := exec.Command("git", args...) // #nosec G204 -- arguments are fixed git init args plus a staged workspace path.
		cmd.Dir = rootDir
		output, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("OnlyMacs could not prepare a git-backed workspace: %s", strings.TrimSpace(string(output)))
		}
	}

	if branch := strings.TrimSpace(manifest.Workspace.GitBranch); branch != "" && branch != "HEAD" {
		cmd := exec.Command("git", "branch", "-M", branch) // #nosec G204 -- branch is derived from sanitized lease metadata.
		cmd.Dir = rootDir
		_, _ = cmd.CombinedOutput()
	}
	return nil
}

func extractOnlyMacsArtifactBundle(bundleData []byte, tempDir string) (string, error) {
	gzipReader, err := gzip.NewReader(bytes.NewReader(bundleData))
	if err != nil {
		return "", fmt.Errorf("OnlyMacs artifact bundle could not be opened: %w", err)
	}
	defer gzipReader.Close()

	tarReader := tar.NewReader(gzipReader)
	topLevel := ""
	extractedFiles := 0
	extractedBytes := int64(0)
	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", fmt.Errorf("OnlyMacs artifact bundle could not be unpacked: %w", err)
		}

		name := path.Clean(strings.TrimSpace(header.Name))
		if name == "." || name == "" {
			continue
		}
		if strings.HasPrefix(name, "../") || name == ".." || strings.HasPrefix(name, "/") {
			return "", fmt.Errorf("OnlyMacs artifact bundle contained an invalid path")
		}

		parts := strings.Split(name, "/")
		if topLevel == "" && len(parts) > 0 {
			topLevel = parts[0]
		}

		targetPath, err := bridgeSafeJoinUnderRoot(tempDir, filepath.FromSlash(name))
		if err != nil {
			return "", fmt.Errorf("OnlyMacs artifact bundle escaped the staging workspace")
		}

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(targetPath, 0o700); err != nil {
				return "", fmt.Errorf("OnlyMacs artifact bundle could not create a directory: %w", err)
			}
		case tar.TypeReg, tar.TypeRegA:
			extractedFiles++
			if extractedFiles > onlyMacsArtifactMaxFiles {
				return "", fmt.Errorf("OnlyMacs artifact bundle contained too many files")
			}
			if header.Size < 0 || extractedBytes+header.Size > onlyMacsArtifactMaxBytes {
				return "", fmt.Errorf("OnlyMacs artifact bundle exceeds the maximum expanded size")
			}
			if err := os.MkdirAll(filepath.Dir(targetPath), 0o700); err != nil {
				return "", fmt.Errorf("OnlyMacs artifact bundle could not create a file directory: %w", err)
			}
			file, err := os.OpenFile(targetPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600) // #nosec G304 G703 -- targetPath is constrained by bridgeSafeJoinUnderRoot.
			if err != nil {
				return "", fmt.Errorf("OnlyMacs artifact bundle could not create a file: %w", err)
			}
			written, err := io.Copy(file, io.LimitReader(tarReader, header.Size+1))
			extractedBytes += written
			if err != nil {
				_ = file.Close()
				return "", fmt.Errorf("OnlyMacs artifact bundle could not write a file: %w", err)
			}
			if written != header.Size {
				_ = file.Close()
				return "", fmt.Errorf("OnlyMacs artifact bundle contained an invalid file size")
			}
			if err := file.Close(); err != nil {
				return "", fmt.Errorf("OnlyMacs artifact bundle could not finalize a file: %w", err)
			}
		default:
			return "", fmt.Errorf("OnlyMacs artifact bundle contains an unsupported entry type")
		}
	}

	if topLevel == "" {
		return "", fmt.Errorf("OnlyMacs artifact bundle was empty")
	}
	return filepath.Join(tempDir, filepath.FromSlash(topLevel)), nil
}

func renderOnlyMacsArtifactContext(payload *onlyMacsArtifactPayload, rootDir string) string {
	var builder strings.Builder
	contract := resolveOnlyMacsArtifactContract(payload.Manifest.RequestIntent, strings.TrimSpace(payload.ExportMode))
	approvedFiles := sortedOnlyMacsApprovedFiles(payload.Manifest.Files)
	requiredSections := payload.Manifest.RequiredSections
	groundingRules := payload.Manifest.GroundingRules
	if len(requiredSections) == 0 {
		requiredSections = contract.requiredSections
	}
	if len(groundingRules) == 0 {
		groundingRules = contract.defaultGroundingRules
	}

	builder.WriteString("OnlyMacs trusted file bundle\n")
	builder.WriteString("Use the approved files below as the ground truth for this request. If you need context that is not present here, say so plainly instead of guessing.\n")
	if schema := strings.TrimSpace(payload.Manifest.Schema); schema != "" {
		builder.WriteString(fmt.Sprintf("Capsule schema: %s\n", schema))
	}
	if trustTier := strings.TrimSpace(payload.Manifest.TrustTier); trustTier != "" {
		builder.WriteString(fmt.Sprintf("Trust tier: %s\n", trustTier))
	}
	if len(payload.Manifest.ContextPacks) > 0 {
		packIDs := make([]string, 0, len(payload.Manifest.ContextPacks))
		for _, pack := range payload.Manifest.ContextPacks {
			if id := strings.TrimSpace(pack.ID); id != "" {
				packIDs = append(packIDs, id)
			}
		}
		if len(packIDs) > 0 {
			builder.WriteString(fmt.Sprintf("Context packs: %s\n", strings.Join(packIDs, ", ")))
		}
	}
	if promptSummary := strings.TrimSpace(payload.Manifest.PromptSummary); promptSummary != "" {
		builder.WriteString(fmt.Sprintf("Original request: %s\n", promptSummary))
	}
	if strings.TrimSpace(payload.Manifest.Lease.ID) != "" {
		builder.WriteString(fmt.Sprintf("Lease: %s (%s)\n", payload.Manifest.Lease.ID, strings.TrimSpace(payload.Manifest.Lease.Mode)))
	}
	if workspaceKind := strings.TrimSpace(payload.Manifest.Workspace.Kind); workspaceKind != "" {
		builder.WriteString(fmt.Sprintf("Workspace mode: %s\n", workspaceKind))
	}
	if contract.heading != "" {
		builder.WriteString("\n")
		builder.WriteString(contract.heading)
		builder.WriteString(":\n")
		if len(requiredSections) > 0 {
			builder.WriteString("- Return these sections in this order: ")
			builder.WriteString(strings.Join(requiredSections, ", "))
			builder.WriteString("\n")
		}
		for _, line := range contract.instructions(approvedFiles) {
			builder.WriteString("- ")
			builder.WriteString(strings.TrimSpace(line))
			builder.WriteString("\n")
		}
		for _, rule := range groundingRules {
			builder.WriteString("- ")
			builder.WriteString(strings.TrimSpace(rule))
			builder.WriteString("\n")
		}
		for _, rule := range payload.Manifest.ContextRequestRules {
			builder.WriteString("- ")
			builder.WriteString(strings.TrimSpace(rule))
			builder.WriteString("\n")
		}
	}
	if len(payload.Manifest.Warnings) > 0 {
		builder.WriteString("\nBundle warnings:\n")
		for _, warning := range payload.Manifest.Warnings {
			builder.WriteString("- ")
			builder.WriteString(strings.TrimSpace(warning))
			builder.WriteString("\n")
		}
	}
	if len(payload.Manifest.Blocked) > 0 {
		builder.WriteString("\nBlocked files:\n")
		for _, blocked := range payload.Manifest.Blocked {
			if strings.TrimSpace(blocked.RelativePath) == "" {
				continue
			}
			builder.WriteString("- ")
			builder.WriteString(strings.TrimSpace(blocked.RelativePath))
			if reason := strings.TrimSpace(blocked.Reason); reason != "" {
				builder.WriteString(" — ")
				builder.WriteString(reason)
			}
			builder.WriteString("\n")
		}
	}
	builder.WriteString("\nApproved files:\n")
	for _, file := range approvedFiles {
		builder.WriteString("- ")
		builder.WriteString(file.RelativePath)
		if category := strings.TrimSpace(file.Category); category != "" {
			builder.WriteString(" [")
			builder.WriteString(category)
			builder.WriteString("]")
		}
		if file.ReviewPriority > 0 {
			builder.WriteString(fmt.Sprintf(" [priority %d]", file.ReviewPriority))
		}
		if file.ExportedBytes > 0 {
			builder.WriteString(fmt.Sprintf(" (%d bytes)", file.ExportedBytes))
		}
		if file.IsRecommended {
			builder.WriteString(" [recommended]")
		}
		if strings.TrimSpace(file.SelectionReason) != "" {
			builder.WriteString(" — selected because ")
			builder.WriteString(strings.TrimSpace(file.SelectionReason))
		}
		if len(file.EvidenceAnchors) > 0 || len(file.EvidenceHints) > 0 {
			builder.WriteString(" — anchors: ")
			builder.WriteString(renderOnlyMacsEvidenceAnchors(file.EvidenceAnchors, file.EvidenceHints))
		}
		if strings.TrimSpace(file.Reason) != "" {
			builder.WriteString(" — ")
			builder.WriteString(strings.TrimSpace(file.Reason))
		}
		builder.WriteString("\n")
	}

	for _, file := range approvedFiles {
		relativePath := strings.TrimSpace(file.RelativePath)
		if relativePath == "" {
			continue
		}
		content, err := bridgeReadRegularFileUnderRoot(rootDir, relativePath)
		if err != nil {
			continue
		}
		text := strings.TrimSpace(string(content))
		if text == "" {
			continue
		}

		builder.WriteString("\n### File: ")
		builder.WriteString(relativePath)
		if category := strings.TrimSpace(file.Category); category != "" {
			builder.WriteString(" [")
			builder.WriteString(category)
			builder.WriteString("]")
		}
		if len(file.EvidenceAnchors) > 0 || len(file.EvidenceHints) > 0 {
			builder.WriteString("\nEvidence anchors: ")
			builder.WriteString(renderOnlyMacsEvidenceAnchors(file.EvidenceAnchors, file.EvidenceHints))
		}
		builder.WriteString("\n```")
		builder.WriteString(languageFenceForPath(relativePath))
		builder.WriteString("\n")
		builder.WriteString(text)
		builder.WriteString("\n```\n")
	}

	return strings.TrimSpace(builder.String())
}

func validateOnlyMacsArtifact(payload *onlyMacsArtifactPayload, rootDir string) error {
	if expiresAt := strings.TrimSpace(payload.Manifest.ExpiresAt); expiresAt != "" {
		parsed, err := time.Parse(time.RFC3339, expiresAt)
		if err != nil {
			return fmt.Errorf("OnlyMacs artifact capsule has an invalid expiry timestamp")
		}
		if time.Now().After(parsed) {
			return fmt.Errorf("OnlyMacs artifact capsule has expired")
		}
	}

	bundleManifest, err := readOnlyMacsArtifactManifestFile(rootDir)
	if err != nil {
		return err
	}
	if err := compareOnlyMacsArtifactManifests(payload.Manifest, bundleManifest); err != nil {
		return err
	}

	if strings.EqualFold(strings.TrimSpace(payload.Manifest.TrustTier), "public_untrusted") && payload.Manifest.AbsolutePathsIncluded {
		return fmt.Errorf("OnlyMacs public capsules must not include absolute paths")
	}
	if strings.EqualFold(strings.TrimSpace(payload.Manifest.TrustTier), "public_untrusted") && strings.TrimSpace(payload.Manifest.WorkspaceRoot) != "" {
		return fmt.Errorf("OnlyMacs public capsules must not disclose the absolute workspace root")
	}

	for _, file := range payload.Manifest.Files {
		relativePath := path.Clean(strings.TrimSpace(file.RelativePath))
		if relativePath == "" || relativePath == "." || strings.HasPrefix(relativePath, "../") || path.IsAbs(relativePath) {
			return fmt.Errorf("OnlyMacs artifact bundle contained an invalid relative path")
		}
		if strings.EqualFold(strings.TrimSpace(payload.Manifest.TrustTier), "public_untrusted") && onlyMacsArtifactPathIsHidden(relativePath) {
			return fmt.Errorf("OnlyMacs public capsules cannot include hidden files")
		}
		if !payload.Manifest.AbsolutePathsIncluded && strings.TrimSpace(file.Path) != "" {
			return fmt.Errorf("OnlyMacs artifact manifest disclosed absolute paths when it should not")
		}
		if file.Status != onlyMacsArtifactFileReady && file.Status != onlyMacsArtifactFileTrimmed {
			continue
		}
		content, err := bridgeReadRegularFileUnderRoot(rootDir, relativePath)
		if err != nil {
			return fmt.Errorf("OnlyMacs artifact bundle is missing approved file %s", relativePath)
		}
		if expected := strings.TrimSpace(file.SHA256); expected != "" {
			sum := sha256.Sum256(content)
			actual := hex.EncodeToString(sum[:])
			if !strings.EqualFold(actual, expected) {
				return fmt.Errorf("OnlyMacs artifact bundle failed file checksum verification for %s", relativePath)
			}
		}
	}

	return nil
}

func readOnlyMacsArtifactManifestFile(rootDir string) (onlyMacsArtifactManifest, error) {
	data, err := bridgeReadRegularFileUnderRoot(rootDir, "manifest.json")
	if err != nil {
		return onlyMacsArtifactManifest{}, fmt.Errorf("OnlyMacs artifact bundle is missing manifest.json")
	}
	var manifest onlyMacsArtifactManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		return onlyMacsArtifactManifest{}, fmt.Errorf("OnlyMacs artifact bundle manifest could not be decoded")
	}
	return manifest, nil
}

func compareOnlyMacsArtifactManifests(expected onlyMacsArtifactManifest, actual onlyMacsArtifactManifest) error {
	if strings.TrimSpace(expected.ID) != "" && expected.ID != actual.ID {
		return fmt.Errorf("OnlyMacs artifact manifest did not match the approved capsule id")
	}
	if schema := strings.TrimSpace(expected.Schema); schema != "" && schema != actual.Schema {
		return fmt.Errorf("OnlyMacs artifact manifest schema mismatch")
	}
	if requestID := strings.TrimSpace(expected.RequestID); requestID != "" && requestID != actual.RequestID {
		return fmt.Errorf("OnlyMacs artifact manifest request id mismatch")
	}
	expectedPaths := onlyMacsArtifactRelativePaths(expected.Files)
	actualPaths := onlyMacsArtifactRelativePaths(actual.Files)
	if len(expectedPaths) != len(actualPaths) {
		return fmt.Errorf("OnlyMacs artifact manifest file list mismatch")
	}
	for idx := range expectedPaths {
		if expectedPaths[idx] != actualPaths[idx] {
			return fmt.Errorf("OnlyMacs artifact manifest file list mismatch")
		}
	}
	return nil
}

func onlyMacsArtifactRelativePaths(files []onlyMacsArtifactManifestFile) []string {
	paths := make([]string, 0, len(files))
	for _, file := range files {
		relativePath := strings.TrimSpace(file.RelativePath)
		if relativePath != "" {
			paths = append(paths, path.Clean(relativePath))
		}
	}
	slices.Sort(paths)
	return paths
}

func onlyMacsArtifactPathIsHidden(relativePath string) bool {
	parts := strings.Split(relativePath, "/")
	for _, part := range parts {
		if strings.HasPrefix(part, ".") {
			return true
		}
	}
	return false
}

type onlyMacsArtifactContract struct {
	heading               string
	requiredSections      []string
	defaultGroundingRules []string
	instructions          func([]onlyMacsArtifactManifestFile) []string
}

func resolveOnlyMacsArtifactContract(requestIntent, exportMode string) onlyMacsArtifactContract {
	switch requestIntent {
	case "grounded_code_review":
		return onlyMacsArtifactContract{
			heading:          "Grounded code review contract",
			requiredSections: []string{"Findings", "Missing Tests", "Referenced Files"},
			defaultGroundingRules: []string{
				"Base every material claim only on the approved files in this bundle.",
				"Prioritize behavioral bugs, regressions, risky assumptions, and missing tests over style-only commentary.",
				"If the approved files are not enough to prove a bug, move that concern into Missing Tests instead of guessing.",
				"When Findings is 'None.', every Missing Tests item must still cite the exact approved file path and line range that justify the gap.",
				"Avoid generic cleanup advice that is not tied to a concrete risk in the approved files.",
				"Always include every required section, even when it is empty. Use 'None.' instead of omitting the section.",
			},
			instructions: func(files []onlyMacsArtifactManifestFile) []string {
				lines := []string{
					"Return at most 3 findings total.",
					"Under Findings, use only these severity labels: [P1], [P2], or [P3]. Do not invent [P4] or higher.",
					"Every finding must include an Evidence line and cite one or more exact approved relative file paths, never a directory name or a vague group label.",
					"Every Missing Tests item must also include an Evidence line whenever the gap is inferred from the approved files.",
					"Each Evidence line must include line-aware citations in this format: src/example.ts:12-18 (\"Quoted heading or snippet\").",
					"Use this exact finding shape:",
					"  [P1] Short title",
					"  Evidence: src/example.ts:12-18 (\"Quoted heading\")",
					"  Impact: one concise sentence tied to that evidence.",
					"Use this exact missing-test shape:",
					"  - Missing test short title",
					"    Evidence: src/example.ts:12-18 (\"Quoted heading\")",
					"    Why: one concise sentence tied to that evidence.",
					"Weight stronger evidence first. Prefer Source, then Config, then Overview, then supporting docs or generated artifacts.",
					"Do not critique OnlyMacs route labels, export metadata, or the review instructions themselves. Review only the approved repo files.",
				}
				if onlyMacsShouldRequireCrossFileFinding(files) {
					lines = append(lines, "Include at least one finding that compares two approved files and calls out a contradiction, mismatch, or handoff gap between them.")
				}
				return lines
			},
		}
	case "grounded_generation":
		return onlyMacsArtifactContract{
			heading:          "Grounded generation contract",
			requiredSections: []string{"Proposed Output", "Open Questions", "Referenced Files"},
			defaultGroundingRules: []string{
				"Base every proposal only on the approved files in this bundle.",
				"Name the target file or output artifact explicitly for every proposed output.",
				"If schema, examples, or workflow docs are incomplete, say so under Open Questions instead of inventing missing rules.",
				"Do not claim any file has already been created or saved.",
				"Always include every required section, even when it is empty. Use 'None.' instead of omitting the section.",
			},
			instructions: func(files []onlyMacsArtifactManifestFile) []string {
				return []string{
					"Return at most 5 proposed outputs total.",
					"Under Proposed Output, use this exact shape:",
					"  Target: path/to/output.ext",
					"  Proposal: one concise sentence describing what to create.",
					"  Evidence: path/to/source.ext:12-18 (\"Quoted heading or snippet\")",
					"Weight schema, examples, and high-priority workflow docs above supporting files.",
					"Keep the proposals concrete enough that a follow-up edit pass could implement them directly.",
				}
			},
		}
	case "grounded_transform":
		return onlyMacsArtifactContract{
			heading:          "Grounded transform contract",
			requiredSections: []string{"Proposed Changes", "Open Questions", "Referenced Files"},
			defaultGroundingRules: []string{
				"Base every proposed change only on the approved files in this bundle.",
				"Name the target file explicitly for every proposed change.",
				"If the approved files are not enough to propose a safe change, say so under Open Questions instead of guessing.",
				"Do not claim any patch has already been applied.",
				"Always include every required section, even when it is empty. Use 'None.' instead of omitting the section.",
			},
			instructions: func(files []onlyMacsArtifactManifestFile) []string {
				return []string{
					"Return at most 5 proposed changes total.",
					"Under Proposed Changes, use this exact shape:",
					"  Target: path/to/file.ext",
					"  Change: one concise sentence describing the edit.",
					"  Evidence: path/to/file.ext:12-18 (\"Quoted heading or snippet\")",
					"Prefer high-confidence changes that clearly follow from the approved schema, examples, or source files.",
				}
			},
		}
	case "grounded_review":
		fallthrough
	default:
		if requestIntent == "grounded_review" || strings.EqualFold(exportMode, "trusted_review_full") {
			return onlyMacsArtifactContract{
				heading:          "Grounded review contract",
				requiredSections: []string{"Findings", "Open Questions", "Referenced Files"},
				defaultGroundingRules: []string{
					"Base every material claim only on the approved files in this bundle.",
					"For each finding, cite the exact approved relative file path that supports it.",
					"If evidence is incomplete or a file is trimmed, say so plainly instead of guessing.",
					"Avoid generic filler or broad advice that is not tied to cited files.",
					"Always include Open Questions, even when there are none. Write 'None.' under that section instead of skipping it.",
					"Always include every required section, even when it is empty. Use 'None.' instead of omitting the section.",
				},
				instructions: func(files []onlyMacsArtifactManifestFile) []string {
					lines := []string{
						"Return at most 3 findings total.",
						"Under Findings, use only these severity labels: [P1], [P2], or [P3]. Do not invent [P4] or higher.",
						"Prefer contradictions, handoff mismatches, or state drift across approved files over single-file wording nitpicks.",
						"Every finding must include an Evidence line and cite one or more exact approved relative file paths, never a directory name or a vague group label.",
						"Each Evidence line must include line-aware citations in this format: docs/example/path.md:12-18 (\"Quoted heading or snippet\").",
						"Use this exact finding shape:",
						"  [P1] Short title",
						"  Evidence: docs/example/path.md:12-18 (\"Quoted heading\")",
						"  Impact: one concise sentence tied to that evidence.",
						"Use this exact open-question shape when you genuinely need more context:",
						"  - Short question",
						"    Evidence: docs/example/path.md:12-18 (\"Quoted heading\")",
						"    Why: one concise sentence about what is still unclear.",
						"Weight stronger evidence first. Prefer Master Docs, then Overview, then Source, then Config, then Scripts, then Schema, then supporting docs or generated artifacts.",
						"Do not critique OnlyMacs route labels, export metadata, or the review instructions themselves. Review only the approved repo files.",
						"If the approved files do not support a claim, put that gap under Open Questions instead of guessing.",
					}
					if onlyMacsShouldRequireCrossFileFinding(files) {
						lines = append(lines, "Include at least one finding that compares two approved files and calls out a contradiction, mismatch, or handoff gap between them.")
					}
					return lines
				},
			}
		}
		return onlyMacsArtifactContract{}
	}
}

func languageFenceForPath(relativePath string) string {
	ext := strings.TrimPrefix(strings.ToLower(filepath.Ext(relativePath)), ".")
	switch ext {
	case "md", "markdown", "txt", "json", "yaml", "yml", "swift", "ts", "tsx", "js", "jsx", "py", "sh", "html", "css":
		return ext
	default:
		return ""
	}
}

func sortedOnlyMacsApprovedFiles(files []onlyMacsArtifactManifestFile) []onlyMacsArtifactManifestFile {
	approved := make([]onlyMacsArtifactManifestFile, 0, len(files))
	for _, file := range files {
		if file.Status != onlyMacsArtifactFileReady && file.Status != onlyMacsArtifactFileTrimmed {
			continue
		}
		approved = append(approved, file)
	}

	slices.SortStableFunc(approved, func(a, b onlyMacsArtifactManifestFile) int {
		if a.ReviewPriority != b.ReviewPriority {
			if a.ReviewPriority > b.ReviewPriority {
				return -1
			}
			return 1
		}
		if a.ExportedBytes != b.ExportedBytes {
			if a.ExportedBytes < b.ExportedBytes {
				return -1
			}
			return 1
		}
		return strings.Compare(a.RelativePath, b.RelativePath)
	})
	return approved
}

func onlyMacsShouldRequireCrossFileFinding(files []onlyMacsArtifactManifestFile) bool {
	count := 0
	for _, file := range files {
		switch strings.TrimSpace(file.Category) {
		case "Master Docs", "Overview", "Source", "Config", "Scripts", "Schema":
			count++
		}
		if count >= 2 {
			return true
		}
	}
	return false
}

func renderOnlyMacsEvidenceAnchors(anchors []onlyMacsArtifactEvidenceAnchor, hints []string) string {
	if len(anchors) > 0 {
		trimmed := make([]string, 0, len(anchors))
		for _, anchor := range anchors {
			text := strings.TrimSpace(anchor.Text)
			if text == "" {
				continue
			}
			if anchor.LineStart > 0 {
				lineRange := fmt.Sprintf("%d", anchor.LineStart)
				if anchor.LineEnd > anchor.LineStart {
					lineRange = fmt.Sprintf("%d-%d", anchor.LineStart, anchor.LineEnd)
				}
				trimmed = append(trimmed, fmt.Sprintf("lines %s %q", lineRange, text))
			} else {
				trimmed = append(trimmed, fmt.Sprintf("%q", text))
			}
			if len(trimmed) >= 3 {
				break
			}
		}
		return strings.Join(trimmed, ", ")
	}

	trimmed := make([]string, 0, len(hints))
	for _, hint := range hints {
		hint = strings.TrimSpace(hint)
		if hint == "" {
			continue
		}
		trimmed = append(trimmed, fmt.Sprintf("%q", hint))
		if len(trimmed) >= 3 {
			break
		}
	}
	return strings.Join(trimmed, ", ")
}
