package agent

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/hivecommons/crux/config"
)

// The capture logic lives in agent/resume; these tests cover the Manager and
// AgentHome wiring around it (hivecommons/hive#9606).

func homeForCapture(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	return home
}

func writeResumeTranscript(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func TestCaptureResumeHandle_UsesAgentHomeAndCodexHome(t *testing.T) {
	home := homeForCapture(t)
	writeResumeTranscript(t, filepath.Join(home, ".copilot", "session-state", "sess-live-0001", "events.jsonl"), "{}\n")
	h, ok := CaptureResumeHandle("scanner", 0, "copilot", time.Now())
	if !ok || h.SessionID != "sess-live-0001" {
		t.Fatalf("handle = %+v, ok = %v", h, ok)
	}

	prev := codexHomePrefix
	codexHomePrefix = filepath.Join(t.TempDir(), "codex-")
	t.Cleanup(func() { codexHomePrefix = prev })
	const id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
	writeResumeTranscript(t, filepath.Join(codexHomePath("scanner"), "sessions", "2026", "09", "30", "rollout-2026-09-30T08-05-47-"+id+".jsonl"), "{}\n")
	h, ok = CaptureResumeHandle("scanner", 0, "codex", time.Now())
	if !ok || h.SessionID != id {
		t.Fatalf("codex handle = %+v, ok = %v", h, ok)
	}
	if !BackendSupportsResumeHandle("codex") || BackendSupportsResumeHandle("agy") {
		t.Error("BackendSupportsResumeHandle does not delegate to the resume package")
	}
}

func TestCaptureResumeHandleIn_ScopesByWorkDir(t *testing.T) {
	home := homeForCapture(t)
	project := filepath.Join(home, ".gemini", "tmp", "scanner")
	writeResumeTranscript(t, filepath.Join(project, ".project_root"), "/data/agents/scanner\n")
	writeResumeTranscript(t, filepath.Join(project, "chats", "session-2026-09-30T08-00-12345678.jsonl"),
		`{"sessionId":"12345678-1111-2222-3333-444444444444"}`+"\n")
	if _, ok := CaptureResumeHandleIn("scanner", 0, "gemini", "/data/agents/scanner", time.Now()); !ok {
		t.Error("gemini session of the agent's work dir was not captured")
	}
	if _, ok := CaptureResumeHandle("scanner", 0, "gemini", time.Now()); ok {
		t.Error("project-scoped backend captured without a work dir")
	}
}

func TestManagerResumeHandle_NilAndUnknownAgent(t *testing.T) {
	var m *Manager
	if _, ok := m.ResumeHandle("scanner"); ok {
		t.Error("nil manager returned a resume handle")
	}
	mgr := &Manager{agents: map[string]*AgentProcess{}}
	if _, ok := mgr.ResumeHandle("scanner"); ok {
		t.Error("unknown agent returned a resume handle")
	}
	mgr.agents["scanner"] = &AgentProcess{Name: "scanner", State: StateStopped}
	if _, ok := mgr.ResumeHandle("scanner"); ok {
		t.Error("stopped agent returned a resume handle")
	}
}

func TestManagerResumeHandle_GeminiUsesAgentWorkDir(t *testing.T) {
	home := homeForCapture(t)
	workRoot := t.TempDir()
	const id = "12345678-1111-2222-3333-444444444444"
	project := filepath.Join(home, ".gemini", "tmp", "scanner")
	writeResumeTranscript(t, filepath.Join(project, ".project_root"), filepath.Join(workRoot, "scanner")+"\n")
	writeResumeTranscript(t, filepath.Join(project, "chats", "session-2026-09-30T08-00-12345678.jsonl"), `{"sessionId":"`+id+`"}`+"\n")
	mgr := &Manager{workDir: workRoot, agents: map[string]*AgentProcess{
		"scanner": {Name: "scanner", State: StateRunning, Config: config.AgentConfig{Backend: "gemini"}},
	}}

	h, ok := mgr.ResumeHandle("scanner")
	if !ok || h.SessionID != id || h.Backend != "gemini" {
		t.Fatalf("handle = %+v, ok = %v", h, ok)
	}
}

func TestManagerResumeHandle_RunningAgentCapturesBackendSession(t *testing.T) {
	home := homeForCapture(t)
	writeResumeTranscript(t, filepath.Join(home, ".copilot", "session-state", "sess-live-0003", "events.jsonl"), "{}\n")
	mgr := &Manager{agents: map[string]*AgentProcess{
		"scanner": {Name: "scanner", State: StateRunning, Config: config.AgentConfig{Backend: "copilot"}},
	}}

	h, ok := mgr.ResumeHandle("scanner")
	if !ok {
		t.Fatal("running copilot agent produced no resume handle")
	}
	if h.SessionID != "sess-live-0003" || h.Backend != "copilot" {
		t.Errorf("handle = %+v", h)
	}
	if h.String() == "" {
		t.Error("String() is empty for a captured handle")
	}
}
