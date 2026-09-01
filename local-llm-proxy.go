package main

import (
  "context"
  "encoding/json"
  "fmt"
  "io"
  "net/http"
  "os"
  "os/exec"
  "strings"
  "time"
)

type Message struct { Role string `json:"role"`; Content any `json:"content"` }
type ChatRequest struct { Model string `json:"model"`; Messages []Message `json:"messages"`; MaxTokens int `json:"max_tokens"`; Temperature float64 `json:"temperature"` }
type Choice struct { Index int `json:"index"`; Message Message `json:"message"`; FinishReason string `json:"finish_reason"` }
type Response struct { ID string `json:"id"`; Object string `json:"object"`; Created int64 `json:"created"`; Model string `json:"model"`; Choices []Choice `json:"choices"` }

func textContent(v any) string {
  switch x := v.(type) {
  case string: return x
  case []any:
    var b strings.Builder
    for _, item := range x { if m, ok := item.(map[string]any); ok { if t, ok := m["text"].(string); ok { b.WriteString(t) } } }
    return b.String()
  default: return fmt.Sprint(x)
  }
}

func handler(w http.ResponseWriter, r *http.Request) {
  if r.URL.Path == "/health" { w.WriteHeader(http.StatusOK); _, _ = w.Write([]byte("ok")); return }
  if r.URL.Path == "/v1/models" { w.Header().Set("Content-Type", "application/json"); _, _ = w.Write([]byte(`{"object":"list","data":[{"id":"picolm-local","object":"model","owned_by":"local"}]}`)); return }
  if r.URL.Path != "/v1/chat/completions" { http.NotFound(w,r); return }
  body, err := io.ReadAll(io.LimitReader(r.Body, 2<<20)); if err != nil { http.Error(w, err.Error(), 400); return }
  var req ChatRequest; if err := json.Unmarshal(body, &req); err != nil { http.Error(w, err.Error(), 400); return }
  var prompt strings.Builder
  for _, m := range req.Messages { prompt.WriteString(m.Role); prompt.WriteString(": "); prompt.WriteString(textContent(m.Content)); prompt.WriteString("\n") }
  max := req.MaxTokens; if max <= 0 { max = 256 }; if max > 1024 { max = 1024 }
  threads := 2
  ctx, cancel := context.WithTimeout(r.Context(), 5*time.Minute); defer cancel()
  args := []string{"/app/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf", "-p", prompt.String(), "-n", fmt.Sprint(max), "-j", fmt.Sprint(threads)}
  cmd := exec.CommandContext(ctx, "/app/picolm", args...)
  out, err := cmd.Output(); if err != nil { http.Error(w, "picolm: "+err.Error(), 500); return }
  content := strings.TrimSpace(string(out))
  resp := Response{ID: fmt.Sprintf("picolm-%d", time.Now().UnixNano()), Object:"chat.completion", Created:time.Now().Unix(), Model:req.Model, Choices:[]Choice{{Index:0, Message:Message{Role:"assistant", Content:content}, FinishReason:"stop"}}}
  w.Header().Set("Content-Type", "application/json"); _ = json.NewEncoder(w).Encode(resp)
}

func main() { mux := http.NewServeMux(); mux.HandleFunc("/health", handler); mux.HandleFunc("/v1/models", handler); mux.HandleFunc("/v1/chat/completions", handler); srv := &http.Server{Addr:"127.0.0.1:8090", Handler:mux, ReadHeaderTimeout:10*time.Second}; if err:=srv.ListenAndServe(); err!=nil && err!=http.ErrServerClosed { os.Exit(1) } }
