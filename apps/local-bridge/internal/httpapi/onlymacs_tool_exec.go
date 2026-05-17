package httpapi

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	onlyMacsWorkspaceChangeRenderLimit = 180_000
)

var (
	onlyMacsExecLookPath                    = exec.LookPath
	onlyMacsExecCommandContext              = exec.CommandContext
	onlyMacsWorkspaceCommandHeartbeatPeriod = 30 * time.Second
)

type onlyMacsWorkspaceTool string

const (
	onlyMacsWorkspaceToolUnknown onlyMacsWorkspaceTool = ""
	onlyMacsWorkspaceToolCodex   onlyMacsWorkspaceTool = "codex"
	onlyMacsWorkspaceToolClaude  onlyMacsWorkspaceTool = "claude"
)

type onlyMacsWorkspaceSnapshotEntry struct {
	Size    int64
	SHA256  string
	Content string
	IsText  bool
}

type onlyMacsWorkspaceChange struct {
	RelativePath string
	Status       string
	Bytes        int64
	Content      string
	IsText       bool
	ApplyPreview string
}

func maybeExecuteOnlyMacsToolWorkspace(ctx context.Context, req chatCompletionsRequest) (bool, int, http.Header, []byte, error) {
	if req.OnlyMacsArtifact == nil {
		return false, 0, nil, nil, nil
	}

	tool := normalizeOnlyMacsWorkspaceTool(req.OnlyMacsArtifact.Manifest.ToolName)
	if tool == onlyMacsWorkspaceToolUnknown {
		return false, 0, nil, nil, nil
	}

	rootDir, cleanup, err := stageOnlyMacsArtifact(req.OnlyMacsArtifact)
	if err != nil {
		return true, 0, nil, nil, err
	}
	defer cleanup()

	baseline, err := captureOnlyMacsWorkspaceSnapshot(rootDir)
	if err != nil {
		return true, 0, nil, nil, err
	}

	prompt := renderOnlyMacsWorkspacePrompt(req.Messages)
	if strings.TrimSpace(prompt) == "" {
		return true, 0, nil, nil, fmt.Errorf("OnlyMacs could not execute this workspace request because no prompt was stored")
	}

	output, err := executeOnlyMacsWorkspaceTool(ctx, tool, rootDir, prompt)
	if err != nil {
		return true, 0, nil, nil, err
	}

	changes, err := collectOnlyMacsWorkspaceChanges(rootDir, baseline)
	if err != nil {
		return true, 0, nil, nil, err
	}

	content := renderOnlyMacsWorkspaceExecutionResult(output, changes)
	body, err := buildOnlyMacsChatCompletionBody(content)
	if err != nil {
		return true, 0, nil, nil, err
	}
	return true, http.StatusOK, http.Header{"Content-Type": []string{"application/json"}}, body, nil
}

func normalizeOnlyMacsWorkspaceTool(name string) onlyMacsWorkspaceTool {
	lowered := strings.ToLower(strings.TrimSpace(name))
	switch {
	case strings.Contains(lowered, "codex"):
		return onlyMacsWorkspaceToolCodex
	case strings.Contains(lowered, "claude"):
		return onlyMacsWorkspaceToolClaude
	default:
		return onlyMacsWorkspaceToolUnknown
	}
}

func renderOnlyMacsWorkspacePrompt(messages []chatMessage) string {
	if len(messages) == 0 {
		return ""
	}
	if len(messages) == 1 && strings.EqualFold(strings.TrimSpace(messages[0].Role), "user") {
		return strings.TrimSpace(messages[0].Content)
	}

	var builder strings.Builder
	builder.WriteString("Use the files in the current working directory as the source of truth for this request. If the staged workspace is missing something you need, say so plainly instead of guessing.\n\nConversation:\n")
	for _, message := range messages {
		content := strings.TrimSpace(message.Content)
		if content == "" {
			continue
		}
		role := strings.TrimSpace(message.Role)
		if role == "" {
			role = "user"
		}
		builder.WriteString("[")
		builder.WriteString(strings.ToUpper(role))
		builder.WriteString("]\n")
		builder.WriteString(content)
		builder.WriteString("\n\n")
	}
	return strings.TrimSpace(builder.String())
}

func executeOnlyMacsWorkspaceTool(ctx context.Context, tool onlyMacsWorkspaceTool, rootDir string, prompt string) (string, error) {
	switch tool {
	case onlyMacsWorkspaceToolCodex:
		return executeOnlyMacsCodexWorkspace(ctx, rootDir, prompt)
	case onlyMacsWorkspaceToolClaude:
		return executeOnlyMacsClaudeWorkspace(ctx, rootDir, prompt)
	default:
		return "", fmt.Errorf("OnlyMacs does not recognize the requested workspace tool")
	}
}

func executeOnlyMacsCodexWorkspace(ctx context.Context, rootDir string, prompt string) (string, error) {
	binaryPath, err := onlyMacsExecLookPath("codex")
	if err != nil {
		return "", fmt.Errorf("OnlyMacs could not run Codex on this provider because the Codex CLI is not installed")
	}

	outputFile, err := os.CreateTemp("", "onlymacs-shell-last-message-*.txt")
	if err != nil {
		return "", fmt.Errorf("OnlyMacs could not create a Codex output file: %w", err)
	}
	outputPath := outputFile.Name()
	if err := outputFile.Close(); err != nil {
		return "", fmt.Errorf("OnlyMacs could not finalize a Codex output file: %w", err)
	}
	defer os.Remove(outputPath)

	cmd := onlyMacsExecCommandContext(ctx, binaryPath,
		"exec",
		"-C", rootDir,
		"--skip-git-repo-check",
		"--sandbox", "workspace-write",
		"--ephemeral",
		"--color", "never",
		"-o", outputPath,
		prompt,
	)
	cmd.Dir = rootDir

	stdout, stderr, logDir, err := runOnlyMacsWorkspaceCommand(cmd, rootDir, "codex")
	lastMessage, _ := os.ReadFile(outputPath) // #nosec G304 -- outputPath is a temp file created by this process.
	result := strings.TrimSpace(string(lastMessage))
	if result == "" {
		result = strings.TrimSpace(stdout + "\n" + stderr)
	}
	if err != nil {
		if result == "" {
			result = strings.TrimSpace(stdout + "\n" + stderr)
		}
		if result == "" {
			result = "Codex exited without returning a final message."
		}
		return "", fmt.Errorf("OnlyMacs could not finish the Codex workspace run: %s (provider logs: %s)", result, logDir)
	}
	if result == "" {
		return "Codex finished without a final message.", nil
	}
	return result, nil
}

func executeOnlyMacsClaudeWorkspace(ctx context.Context, rootDir string, prompt string) (string, error) {
	if !onlyMacsRemoteClaudeWorkspaceAllowed() {
		return "", fmt.Errorf("OnlyMacs remote Claude Code workspace execution is disabled by default; set ONLYMACS_ALLOW_REMOTE_CLAUDE_WORKSPACE=1 on this provider to opt in")
	}
	binaryPath, err := onlyMacsExecLookPath("claude")
	if err != nil {
		return "", fmt.Errorf("OnlyMacs could not run Claude Code on this provider because the Claude CLI is not installed")
	}

	cmd := onlyMacsExecCommandContext(ctx, binaryPath,
		"-p",
		"--add-dir", rootDir,
		"--permission-mode", "bypassPermissions",
		prompt,
	)
	cmd.Dir = rootDir

	stdout, stderr, logDir, err := runOnlyMacsWorkspaceCommand(cmd, rootDir, "claude")
	result := strings.TrimSpace(stdout)
	if result == "" {
		result = strings.TrimSpace(stderr)
	}
	if err != nil {
		if result == "" {
			result = "Claude Code exited without returning a final message."
		}
		return "", fmt.Errorf("OnlyMacs could not finish the Claude Code workspace run: %s (provider logs: %s)", result, logDir)
	}
	if result == "" {
		return "Claude Code finished without a final message.", nil
	}
	return result, nil
}

func onlyMacsRemoteClaudeWorkspaceAllowed() bool {
	return strings.TrimSpace(os.Getenv("ONLYMACS_ALLOW_REMOTE_CLAUDE_WORKSPACE")) == "1"
}

func runOnlyMacsWorkspaceCommand(cmd *exec.Cmd, rootDir string, toolName string) (string, string, string, error) {
	logDir := filepath.Join(filepath.Dir(rootDir), "provider-logs")
	_ = os.MkdirAll(logDir, 0o700)
	stdoutPath := filepath.Join(logDir, toolName+"-stdout.log")
	stderrPath := filepath.Join(logDir, toolName+"-stderr.log")
	heartbeatPath := filepath.Join(logDir, toolName+"-heartbeat.jsonl")

	stdoutFile, stdoutErr := os.Create(stdoutPath) // #nosec G304 -- stdoutPath is under provider-logs beside the staged workspace.
	if stdoutErr != nil {
		return "", "", logDir, stdoutErr
	}
	defer stdoutFile.Close()
	stderrFile, stderrErr := os.Create(stderrPath) // #nosec G304 -- stderrPath is under provider-logs beside the staged workspace.
	if stderrErr != nil {
		return "", "", logDir, stderrErr
	}
	defer stderrFile.Close()

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = io.MultiWriter(&stdout, stdoutFile)
	cmd.Stderr = io.MultiWriter(&stderr, stderrFile)

	stopHeartbeat := writeOnlyMacsWorkspaceCommandHeartbeat(heartbeatPath, toolName)
	defer stopHeartbeat("finished")
	err := cmd.Run()
	if err != nil {
		stopHeartbeat("failed")
	}
	return strings.TrimSpace(stdout.String()), strings.TrimSpace(stderr.String()), logDir, err
}

func writeOnlyMacsWorkspaceCommandHeartbeat(path string, toolName string) func(string) {
	startedAt := time.Now().UTC()
	file, err := os.Create(path) // #nosec G304 -- heartbeat path is under provider-logs beside the staged workspace.
	if err != nil {
		return func(string) {}
	}
	var closed bool
	writeEvent := func(status string) {
		if closed {
			return
		}
		payload, marshalErr := json.Marshal(map[string]any{
			"event":      "provider_workspace_heartbeat",
			"tool":       toolName,
			"status":     status,
			"elapsed_ms": time.Since(startedAt).Milliseconds(),
			"timestamp":  time.Now().UTC().Format(time.RFC3339Nano),
		})
		if marshalErr != nil {
			return
		}
		_, _ = file.Write(append(payload, '\n'))
		_ = file.Sync()
	}

	writeEvent("started")
	done := make(chan struct{})
	period := onlyMacsWorkspaceCommandHeartbeatPeriod
	if period > 0 {
		go func() {
			ticker := time.NewTicker(period)
			defer ticker.Stop()
			for {
				select {
				case <-done:
					return
				case <-ticker.C:
					writeEvent("running")
				}
			}
		}()
	}

	return func(status string) {
		if closed {
			return
		}
		close(done)
		writeEvent(status)
		closed = true
		_ = file.Close()
	}
}

func captureOnlyMacsWorkspaceSnapshot(rootDir string) (map[string]onlyMacsWorkspaceSnapshotEntry, error) {
	snapshot := make(map[string]onlyMacsWorkspaceSnapshotEntry)
	err := filepath.WalkDir(rootDir, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return nil
		}
		relative, err := filepath.Rel(rootDir, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		data, err := bridgeReadRegularFileUnderRoot(rootDir, relative)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(data)
		content, isText := renderOnlyMacsWorkspaceChangeContent(data)
		snapshot[relative] = onlyMacsWorkspaceSnapshotEntry{
			Size:    int64(len(data)),
			SHA256:  hex.EncodeToString(sum[:]),
			Content: content,
			IsText:  isText,
		}
		return nil
	})
	return snapshot, err
}

func collectOnlyMacsWorkspaceChanges(rootDir string, baseline map[string]onlyMacsWorkspaceSnapshotEntry) ([]onlyMacsWorkspaceChange, error) {
	changes := make([]onlyMacsWorkspaceChange, 0)
	currentPaths := make(map[string]struct{})
	err := filepath.WalkDir(rootDir, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return nil
		}
		relative, err := filepath.Rel(rootDir, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		currentPaths[relative] = struct{}{}

		data, err := bridgeReadRegularFileUnderRoot(rootDir, relative)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(data)
		hash := hex.EncodeToString(sum[:])
		if before, ok := baseline[relative]; ok && before.SHA256 == hash {
			return nil
		}

		status := "created"
		if _, existed := baseline[relative]; existed {
			status = "modified"
		}
		text, isText := renderOnlyMacsWorkspaceChangeContent(data)
		before := baseline[relative]
		changes = append(changes, onlyMacsWorkspaceChange{
			RelativePath: relative,
			Status:       status,
			Bytes:        int64(len(data)),
			Content:      text,
			IsText:       isText,
			ApplyPreview: renderOnlyMacsWorkspaceApplyPreview(relative, before.Content, text, before.IsText || isText),
		})
		return nil
	})
	if err != nil {
		return nil, err
	}

	for relative := range baseline {
		if _, exists := currentPaths[relative]; exists {
			continue
		}
		changes = append(changes, onlyMacsWorkspaceChange{
			RelativePath: relative,
			Status:       "deleted",
			Bytes:        0,
			IsText:       baseline[relative].IsText,
			ApplyPreview: renderOnlyMacsWorkspaceApplyPreview(relative, baseline[relative].Content, "", baseline[relative].IsText),
		})
	}

	sort.Slice(changes, func(i, j int) bool {
		return changes[i].RelativePath < changes[j].RelativePath
	})
	return changes, nil
}

func renderOnlyMacsWorkspaceChangeContent(data []byte) (string, bool) {
	if len(data) == 0 {
		return "", true
	}
	if bytesContainNUL(data) || !utf8.Valid(data) {
		return "", false
	}
	return strings.TrimSpace(string(data)), true
}

func bytesContainNUL(data []byte) bool {
	for _, value := range data {
		if value == 0 {
			return true
		}
	}
	return false
}

func renderOnlyMacsWorkspaceExecutionResult(output string, changes []onlyMacsWorkspaceChange) string {
	output = strings.TrimSpace(output)
	var builder strings.Builder
	if output != "" {
		builder.WriteString(output)
	}

	if len(changes) == 0 {
		if builder.Len() == 0 {
			builder.WriteString("OnlyMacs workspace execution finished without textual output.")
		}
		return builder.String()
	}

	if builder.Len() > 0 {
		builder.WriteString("\n\n---\n\n")
	}
	builder.WriteString("Apply Preview:\n")

	remaining := onlyMacsWorkspaceChangeRenderLimit
	for _, change := range changes {
		if strings.TrimSpace(change.ApplyPreview) == "" {
			continue
		}
		builder.WriteString("```diff\n")
		builder.WriteString(strings.TrimSpace(change.ApplyPreview))
		builder.WriteString("\n```\n")
	}

	builder.WriteString("\nChanged files from the staged bundle:\n")
	for _, change := range changes {
		builder.WriteString("- ")
		builder.WriteString(change.RelativePath)
		builder.WriteString(" (")
		builder.WriteString(change.Status)
		builder.WriteString(", ")
		builder.WriteString(ByteCountFormatterString(change.Bytes))
		builder.WriteString(")\n")

		if !change.IsText || change.Content == "" || change.Status == "deleted" {
			continue
		}

		content := change.Content
		if len(content) > remaining {
			if remaining <= 0 {
				builder.WriteString("  Content omitted because the staged workspace diff is large.\n")
				continue
			}
			content = strings.TrimSpace(content[:remaining])
			builder.WriteString("  Partial content:\n")
		}

		builder.WriteString("```")
		builder.WriteString(languageFenceForPath(change.RelativePath))
		builder.WriteString("\n")
		builder.WriteString(content)
		builder.WriteString("\n```\n")
		remaining -= len(content)
	}

	return strings.TrimSpace(builder.String())
}

func renderOnlyMacsWorkspaceApplyPreview(relativePath string, beforeContent string, afterContent string, isText bool) string {
	if !isText || beforeContent == afterContent {
		return ""
	}

	tempDir, err := os.MkdirTemp("", "onlymacs-diff-*")
	if err != nil {
		return ""
	}
	defer os.RemoveAll(tempDir)

	beforePath := filepath.Join(tempDir, "before")
	afterPath := filepath.Join(tempDir, "after")
	if err := os.WriteFile(beforePath, []byte(beforeContent), 0o600); err != nil {
		return ""
	}
	if err := os.WriteFile(afterPath, []byte(afterContent), 0o600); err != nil {
		return ""
	}

	cmd := exec.Command("git", // #nosec G204 -- git is a fixed binary and compared files are temp files created above.
		"diff",
		"--no-index",
		"--no-ext-diff",
		"--no-color",
		"--src-prefix=a/",
		"--dst-prefix=b/",
		"--",
		beforePath,
		afterPath,
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); !ok || exitErr.ExitCode() > 1 {
			return ""
		}
	}
	diff := strings.TrimSpace(string(output))
	if diff == "" {
		return ""
	}
	diff = strings.ReplaceAll(diff, beforePath, "a/"+relativePath)
	diff = strings.ReplaceAll(diff, afterPath, "b/"+relativePath)
	return diff
}

func buildOnlyMacsChatCompletionBody(content string) ([]byte, error) {
	payload := map[string]any{
		"id":     "onlymacs-workspace-tool",
		"object": "chat.completion",
		"choices": []map[string]any{
			{
				"index": 0,
				"message": map[string]any{
					"role":    "assistant",
					"content": content,
				},
				"finish_reason": "stop",
			},
		},
	}
	return json.Marshal(payload)
}

func extractOnlyMacsAssistantContent(body []byte) string {
	var payload struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return ""
	}
	if len(payload.Choices) == 0 {
		return ""
	}
	return strings.TrimSpace(payload.Choices[0].Message.Content)
}

func buildOnlyMacsChatCompletionStreamBody(content string) ([]byte, error) {
	chunks := []map[string]any{
		{
			"id":     "onlymacs-workspace-tool",
			"object": "chat.completion.chunk",
			"choices": []map[string]any{
				{
					"index": 0,
					"delta": map[string]any{
						"role":    "assistant",
						"content": content,
					},
				},
			},
		},
	}

	var builder strings.Builder
	for _, chunk := range chunks {
		payload, err := json.Marshal(chunk)
		if err != nil {
			return nil, err
		}
		builder.WriteString("data: ")
		builder.Write(payload)
		builder.WriteString("\n\n")
	}
	builder.WriteString("data: [DONE]\n\n")
	return []byte(builder.String()), nil
}

func ByteCountFormatterString(value int64) string {
	if value <= 0 {
		return "0 B"
	}
	return ByteCountFormatterStringImpl(value)
}

func ByteCountFormatterStringImpl(value int64) string {
	units := []string{"B", "KB", "MB", "GB"}
	size := float64(value)
	unit := 0
	for size >= 1024 && unit < len(units)-1 {
		size /= 1024
		unit++
	}
	if unit == 0 {
		return fmt.Sprintf("%d %s", value, units[unit])
	}
	return fmt.Sprintf("%.0f %s", size, units[unit])
}
