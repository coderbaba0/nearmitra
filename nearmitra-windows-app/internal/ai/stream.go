package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"nearmitra-windows-app/internal/config"
)

// StreamSharedResponse uses only the owner's configured engine and never changes My AI state.
func (s *AIService) StreamSharedResponse(ctx context.Context, prompt string, emit func(string) error) error {
	cfg := config.Get().GetConfig().AIConfig
	if !cfg.Enabled {
		return fmt.Errorf("AI is disabled on this desktop")
	}
	if strings.TrimSpace(prompt) == "" {
		return fmt.Errorf("Prompt is empty")
	}
	if cfg.Provider != "ollama" {
		switch cfg.Provider {
		case "gemini":
			if strings.TrimSpace(cfg.GeminiAPIKey) == "" {
				return fmt.Errorf("The host's Gemini API key is not configured")
			}
		case "openai":
			if strings.TrimSpace(cfg.OpenAIAPIKey) == "" {
				return fmt.Errorf("The host's OpenAI API key is not configured")
			}
		case "groq":
			if strings.TrimSpace(cfg.GroqAPIKey) == "" {
				return fmt.Errorf("The host's Groq API key is not configured")
			}
		default:
			return fmt.Errorf("The host AI provider is not configured")
		}
		text, err := s.GenerateSharedResponse(prompt)
		if err != nil {
			return err
		}
		return emit(text)
	}
	endpoint := strings.TrimRight(cfg.OllamaURL, "/")
	if endpoint == "" {
		endpoint = "http://127.0.0.1:11434"
	}
	model := cfg.OllamaModel
	if model == "" {
		return fmt.Errorf("Select an installed Ollama model in My AI settings")
	}
	data, err := json.Marshal(map[string]interface{}{"model": model, "prompt": prompt, "system": cfg.SystemPrompt, "stream": true, "options": map[string]interface{}{"temperature": cfg.Temperature}})
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint+"/api/generate", bytes.NewReader(data))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	// The context owns the whole generation deadline; model loading can exceed 30 seconds.
	client := &http.Client{Timeout: 5 * time.Minute}
	response, err := client.Do(request)
	if err != nil {
		return fmt.Errorf("Host Ollama is unavailable: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
		return fmt.Errorf("Ollama error (%d): %s", response.StatusCode, strings.TrimSpace(string(body)))
	}
	decoder := json.NewDecoder(response.Body)
	for {
		var part struct {
			Response string `json:"response"`
			Error    string `json:"error"`
			Done     bool   `json:"done"`
		}
		if err = decoder.Decode(&part); err != nil {
			if err == io.EOF {
				return fmt.Errorf("Ollama response ended before completion")
			}
			return err
		}
		if part.Error != "" {
			return fmt.Errorf("Ollama: %s", part.Error)
		}
		if part.Response != "" {
			if err = emit(part.Response); err != nil {
				return err
			}
		}
		if part.Done {
			s.mu.Lock()
			s.promptsServed++
			s.mu.Unlock()
			return nil
		}
	}
}
