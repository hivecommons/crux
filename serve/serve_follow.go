package serve

import (
	"fmt"
	"net/http"
	"time"

	"github.com/hivecommons/crux"
	"github.com/hivecommons/crux/api"
)

// followWindow is how many ring-buffer lines each follow poll asks for when
// the runtime cannot hand out lines by sequence number.
const followWindow = 200

// followLogs streams new ring-buffer lines as api.EventLog records until the
// client goes away or the runtime stops answering.
func (s *Server) followLogs(w http.ResponseWriter, r *http.Request, name string) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		s.writeError(w, http.StatusInternalServerError, api.CodeRuntime, "streaming is not supported on this connection")
		return
	}
	since, bySeq := s.Runtime.(crux.BufferSinceReader)
	var seq uint64
	var prev []string
	var err error
	if bySeq {
		prev, seq, err = since.GetBufferSince(name, 0)
	} else {
		prev, err = s.Runtime.GetBufferOutput(name, followWindow)
	}
	if err != nil {
		s.writeError(w, http.StatusInternalServerError, api.CodeRuntime, fmt.Sprintf("logs %s: %v", name, err))
		return
	}
	s.startStream(w)
	flusher.Flush()
	if len(prev) > 0 {
		if api.WriteEvent(w, api.EventLog, api.LogChunk{Agent: name, Lines: prev}) != nil {
			return
		}
		flusher.Flush()
	}
	ticker := time.NewTicker(s.PollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-ticker.C:
			if bySeq {
				fresh, next, err := since.GetBufferSince(name, seq)
				if err != nil {
					_ = api.WriteEvent(w, api.EventState, api.Event{Time: s.now(), Type: api.EventState, Agent: name, Detail: err.Error()})
					flusher.Flush()
					return
				}
				seq = next
				if len(fresh) > 0 {
					if api.WriteEvent(w, api.EventLog, api.LogChunk{Agent: name, Lines: fresh}) != nil {
						return
					}
					flusher.Flush()
				}
				continue
			}
			cur, err := s.Runtime.GetBufferOutput(name, followWindow)
			if err != nil {
				_ = api.WriteEvent(w, api.EventState, api.Event{Time: s.now(), Type: api.EventState, Agent: name, Detail: err.Error()})
				flusher.Flush()
				return
			}
			if fresh := newTail(prev, cur); len(fresh) > 0 {
				if api.WriteEvent(w, api.EventLog, api.LogChunk{Agent: name, Lines: fresh}) != nil {
					return
				}
				flusher.Flush()
			}
			prev = cur
		}
	}
}

// newTail returns the lines of cur that were not already seen in prev,
// treating both as windows onto the same append-only buffer: the longest
// suffix of prev that is a prefix of cur is the overlap. It is the CLI's
// stream rule (crux/cli.newTail) applied server side.
func newTail(prev, cur []string) []string {
	max := len(prev)
	if len(cur) < max {
		max = len(cur)
	}
	for k := max; k > 0; k-- {
		if equalLines(prev[len(prev)-k:], cur[:k]) {
			return cur[k:]
		}
	}
	return cur
}

func equalLines(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
