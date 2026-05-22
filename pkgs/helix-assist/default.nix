{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "helix-assist";
  version = "1.0.12";

  src = fetchFromGitHub {
    owner = "leona";
    repo = "helix-assist";
    rev = "v${version}";
    hash = "sha256-pAbWGKV0Xu1wFSven4n32eq88fLeIbyA5imnlAFt+0c=";
  };

  subPackages = [ "cmd/helix-assist" ];

  vendorHash = null;

  # Patches: Chat Completions API + fix insert text replacing instead of appending
  postPatch = ''
    cat > internal/providers/openai.go << 'PATCHEOF'
    package providers

    import (
      "bytes"
      "context"
      "encoding/json"
      "fmt"
      "io"
      "net/http"
      "strings"
      "time"

      "github.com/leona/helix-assist/internal/lsp"
      "github.com/leona/helix-assist/internal/util"
    )

    type OpenAIProvider struct {
      apiKey    string
      model     string
      chatModel string
      endpoint  string
      timeout   time.Duration
      logger    *lsp.Logger
    }

    type chatMessage struct {
      Role    string `json:"role"`
      Content string `json:"content"`
    }

    type thinkingConfig struct {
      Type string `json:"type"`
    }

    type chatCompletionRequest struct {
      Model       string          `json:"model"`
      Messages    []chatMessage   `json:"messages"`
      MaxTokens   int             `json:"max_tokens,omitempty"`
      Temperature float64         `json:"temperature,omitempty"`
      N           int             `json:"n,omitempty"`
      Stream      bool            `json:"stream"`
      Thinking    *thinkingConfig `json:"thinking,omitempty"`
    }

    type chatCompletionResponse struct {
      Choices []struct {
        Message struct {
          Content string `json:"content"`
        } `json:"message"`
      } `json:"choices"`
    }

    func NewOpenAIProvider(apiKey, model, chatModel, endpoint string, timeoutMs int, logger *lsp.Logger) *OpenAIProvider {
      if chatModel == "" {
        chatModel = model
      }
      return &OpenAIProvider{
        apiKey:    apiKey,
        model:     model,
        chatModel: chatModel,
        endpoint:  strings.TrimSuffix(endpoint, "/"),
        timeout:   time.Duration(timeoutMs) * time.Millisecond,
        logger:    logger,
      }
    }

    func (p *OpenAIProvider) Completion(ctx context.Context, req CompletionRequest, filepath, languageID string, numSuggestions int) ([]string, error) {
      systemPrompt := BuildCompletionSystemPrompt(languageID)
      userPrompt := BuildCompletionUserPrompt(filepath, req.ContentBefore, req.ContentAfter)

      results := make([]string, 0, numSuggestions)

      for i := 0; i < numSuggestions; i++ {
        chatReq := chatCompletionRequest{
          Model: p.model,
          Messages: []chatMessage{
            {Role: "system", Content: systemPrompt},
            {Role: "user", Content: userPrompt},
          },
          Temperature: 0.2 + float64(i)*0.1,
          MaxTokens:   256,
          N:           1,
          Stream:      false,
          Thinking:    &thinkingConfig{Type: "disabled"},
        }

        resp, err := p.doRequest(ctx, "", chatReq)
        if err != nil {
          if len(results) > 0 {
            break
          }
          return nil, err
        }

        var chatResp chatCompletionResponse
        if err := json.Unmarshal(resp, &chatResp); err != nil {
          if len(results) > 0 {
            break
          }
          return nil, fmt.Errorf("parse response: %w", err)
        }

        if len(chatResp.Choices) > 0 && chatResp.Choices[0].Message.Content != "" {
          results = append(results, chatResp.Choices[0].Message.Content)
        }
      }

      return util.UniqueStrings(results), nil
    }

    func (p *OpenAIProvider) Chat(ctx context.Context, query, content, filepath, languageID string) (*ChatResponse, error) {
      cleanFilepath := strings.TrimPrefix(filepath, "file://")

      systemPrompt := BuildChatSystemPrompt(languageID)
      userContent := BuildChatUserPrompt(languageID, cleanFilepath, content, query)

      chatReq := chatCompletionRequest{
        Model: p.chatModel,
        Messages: []chatMessage{
          {Role: "system", Content: systemPrompt},
          {Role: "user", Content: userContent},
        },
        N:        1,
        Stream:   false,
        Thinking: &thinkingConfig{Type: "disabled"},
      }

      jsonReq, _ := json.MarshalIndent(chatReq, "", "  ")
      p.logger.Log("DEBUG [OpenAI Chat]: Request:", string(jsonReq))

      resp, err := p.doRequest(ctx, "", chatReq)
      if err != nil {
        return nil, err
      }

      p.logger.Log("DEBUG [OpenAI Chat]: Raw response:", string(resp))

      var chatResp chatCompletionResponse
      if err := json.Unmarshal(resp, &chatResp); err != nil {
        return nil, fmt.Errorf("parse response: %w", err)
      }

      if len(chatResp.Choices) == 0 || chatResp.Choices[0].Message.Content == "" {
        return nil, fmt.Errorf("no completion found")
      }

      p.logger.Log("DEBUG [OpenAI Chat]: Extracted text:", chatResp.Choices[0].Message.Content)
      return &ChatResponse{Result: chatResp.Choices[0].Message.Content}, nil
    }

    func (p *OpenAIProvider) doRequest(ctx context.Context, endpoint string, body any) ([]byte, error) {
      jsonBody, err := json.Marshal(body)
      if err != nil {
        return nil, fmt.Errorf("marshal request: %w", err)
      }

      ctx, cancel := context.WithTimeout(ctx, p.timeout)
      defer cancel()

      url := p.endpoint + endpoint
      req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(jsonBody))
      if err != nil {
        return nil, fmt.Errorf("create request: %w", err)
      }

      req.Header.Set("Content-Type", "application/json")
      req.Header.Set("Authorization", "Bearer "+p.apiKey)

      resp, err := http.DefaultClient.Do(req)
      if err != nil {
        return nil, fmt.Errorf("request failed: %w", err)
      }
      defer resp.Body.Close()

      respBody, err := io.ReadAll(resp.Body)
      if err != nil {
        return nil, fmt.Errorf("read response: %w", err)
      }

      if resp.StatusCode != http.StatusOK {
        return nil, fmt.Errorf("API error (status %d): %s", resp.StatusCode, string(respBody))
      }

      return respBody, nil
    }
    PATCHEOF

    # Fix InsertText to use full hint, not prefix-trimmed version
    sed -i 's/\thint = strings.TrimSpace(hint)/\tinsertText := strings.TrimSpace(hint)\n\thint = strings.TrimSpace(hint)/' internal/handlers/completions.go
    sed -i 's/\t\tInsertText:          hint,/\t\tInsertText:          insertText,/' internal/handlers/completions.go
    sed -i 's/\t\tDetail:              hint,/\t\tDetail:              insertText,/' internal/handlers/completions.go
  '';

  meta = with lib; {
    description = "Code assistant language server for Helix with OpenAI/Anthropic support";
    homepage = "https://github.com/leona/helix-assist";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
