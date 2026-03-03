{ pkgs, ... }:
{
  programs.opencode = {
    enable = true;
    settings = {
      theme = "gruvbox";

      model = "deepseek/deepseek-v3.2";

      small_model = "deepseek/deepseek-v3.2";

      agent = {
        code-reviewer = {
          description = "Reviews code for security vulnerabilities, performance issues, and language standards compliance";
          mode = "subagent";
          model = "deepseek/deepseek-v3.2";
          prompt = "You are a code reviewer specializing in security, performance, and language standards.\n\nFocus on:\n- Security vulnerabilities (SQL injection, XSS, auth issues, secrets exposure, etc.)\n- Performance bottlenecks and inefficiencies\n- Language-specific best practices and coding standards\n- Code quality and maintainability concerns\n\nProvide constructive feedback with specific recommendations. Do not make changes - only analyze and suggest improvements.";
          tools = {
            read = true;
            grep = true;
            write = false;
            edit = false;
            bash = false;
          };
        };

        docs-generator = {
          description = "Generates project documentation in markdown format without emojis";
          mode = "subagent";
          model = "deepseek/deepseek-v3.2";
          prompt = "You are a technical documentation generator. Generate clear, comprehensive documentation in markdown format.\n\nGuidelines:\n- Use standard markdown syntax only\n- Do NOT use emojis unless explicitly specified by the user\n- Use code blocks with appropriate language identifiers\n- Include examples where helpful\n- Keep explanations clear and concise\n- Use proper heading hierarchy\n- Focus on clarity and readability";
          tools = {
            read = true;
            grep = true;
            write = true;
            edit = true;
            bash = false;
          };
        };

        git = {
          description = "Helps with git operations - diffs, commits, status, and more";
          mode = "subagent";
          model = "deepseek/deepseek-v3.2";
          prompt = "You are a git assistant. Help with various git operations as requested.\n\nGuidelines:\n- When asked for diff/status, use bash to run git commands and show the output\n- When asked to create a commit message, use chat context and git diff to understand what changed\n- Focus on the WHY, not just the WHAT - explain the reason for changes\n- Keep commit messages concise - one sentence if possible, more if needed\n- Use imperative mood (e.g., \"Add\", \"Fix\", \"Update\" not \"Added\", \"Fixed\", \"Updated\")\n- If no specific action requested, just have a conversation about the git state\n- Do NOT auto-commit - only create messages when explicitly asked\n- Example workflows:\n  - User: \"@git diff\" -> Run git diff and explain what changed\n  - User: \"@git commit\" -> Analyze diff and suggest a commit message\n  - User: \"@git status\" -> Run git status and explain current state";
          tools = {
            read = true;
            grep = true;
            write = false;
            edit = false;
            bash = true;
          };
        };
      };
    };
  };
}
