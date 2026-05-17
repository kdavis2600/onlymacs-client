package httpapi

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRunOnlyMacsWorkspaceCommandWritesStdoutStderrAndHeartbeatLogs(t *testing.T) {
	previousHeartbeatPeriod := onlyMacsWorkspaceCommandHeartbeatPeriod
	onlyMacsWorkspaceCommandHeartbeatPeriod = time.Millisecond
	t.Cleanup(func() {
		onlyMacsWorkspaceCommandHeartbeatPeriod = previousHeartbeatPeriod
	})

	tempDir := t.TempDir()
	rootDir := filepath.Join(tempDir, "workspace")
	if err := os.MkdirAll(rootDir, 0o700); err != nil {
		t.Fatalf("create workspace: %v", err)
	}

	cmd := exec.Command("sh", "-c", "printf stdout-value; printf stderr-value >&2")
	cmd.Dir = rootDir
	stdout, stderr, logDir, err := runOnlyMacsWorkspaceCommand(cmd, rootDir, "codex")
	if err != nil {
		t.Fatalf("run workspace command: %v", err)
	}
	if stdout != "stdout-value" || stderr != "stderr-value" {
		t.Fatalf("expected captured stdout/stderr, got stdout=%q stderr=%q", stdout, stderr)
	}

	stdoutLog, err := os.ReadFile(filepath.Join(logDir, "codex-stdout.log"))
	if err != nil {
		t.Fatalf("read stdout log: %v", err)
	}
	if string(stdoutLog) != "stdout-value" {
		t.Fatalf("expected stdout log, got %q", string(stdoutLog))
	}
	stderrLog, err := os.ReadFile(filepath.Join(logDir, "codex-stderr.log"))
	if err != nil {
		t.Fatalf("read stderr log: %v", err)
	}
	if string(stderrLog) != "stderr-value" {
		t.Fatalf("expected stderr log, got %q", string(stderrLog))
	}
	heartbeatLog, err := os.ReadFile(filepath.Join(logDir, "codex-heartbeat.jsonl"))
	if err != nil {
		t.Fatalf("read heartbeat log: %v", err)
	}
	if !strings.Contains(string(heartbeatLog), `"status":"started"`) || !strings.Contains(string(heartbeatLog), `"status":"finished"`) {
		t.Fatalf("expected heartbeat start and finish events, got %s", string(heartbeatLog))
	}
}
