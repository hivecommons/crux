package agent

import (
	"path/filepath"
	"time"

	"github.com/hivecommons/crux"
	"github.com/hivecommons/crux/agent/resume"
)

// ResumeHandle is crux.ResumeHandle: a backend-native conversation that
// can be resumed after the authoring tmux pane is gone.
type ResumeHandle = crux.ResumeHandle

// BackendSupportsResumeHandle reports whether a backend keeps a transcript the
// hive can capture a resume id from.
func BackendSupportsResumeHandle(backend string) bool {
	return resume.Supports(backend)
}

// CaptureResumeHandle names the newest conversation the agent's backend has
// persisted under its own HOME, or reports false when it keeps none. Backends
// whose session tree is scoped by project (gemini, pi, omp) need the agent's
// working directory; use CaptureResumeHandleIn for those.
func CaptureResumeHandle(agentName string, uid int, backend string, now time.Time) (ResumeHandle, bool) {
	return CaptureResumeHandleIn(agentName, uid, backend, "", now)
}

// CaptureResumeHandleIn is CaptureResumeHandle for an agent whose CLI runs in
// workDir. For a project-scoped backend only sessions of that project are
// considered, and an empty workDir yields no handle.
func CaptureResumeHandleIn(agentName string, uid int, backend, workDir string, now time.Time) (ResumeHandle, bool) {
	return resume.Capture(backend, AgentHome(agentName, uid, backend), codexHomePath(agentName), workDir, now)
}

// ResumeHandle captures the backend-native resume handle of the named agent's
// current conversation, or false when the agent is unknown, not running, or
// on a backend with no capturable handle.
func (m *Manager) ResumeHandle(name string) (ResumeHandle, bool) {
	if m == nil {
		return ResumeHandle{}, false
	}
	m.mu.RLock()
	agent, found := m.agents[name]
	if !found || agent == nil || agent.State != StateRunning {
		m.mu.RUnlock()
		return ResumeHandle{}, false
	}
	backend, uid := effectiveBackend(agent), agent.UID
	workDir := ""
	if m.workDir != "" {
		workDir = filepath.Join(m.workDir, name)
	}
	m.mu.RUnlock()
	return CaptureResumeHandleIn(name, uid, backend, workDir, time.Now())
}
