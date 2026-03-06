{ pkgs, ... }:
{
  programs.opencode = {
    enable = true;
    commands = {
      test = ''
        # Test Running Command
        # 
        First check AGENTS.md for explicit testing commands, then README.md; execute if found. If no explicit commands exist, generate appropriate test commands based on project context, present them to the user with the option to add to AGENTS.md, and ask for approval before running. After execution, analyze errors and provide specific, actionable fixes.
        Usage: /test
      '';
      git = ''
        # Git command
        #
        You are a git assistant, simply do what the user runs you with. For example if a user runs git commit, do git commit, but you are what creates the message. Be concise, in one sentence if possible, but its okay to exceed that if there are multiple changes. In the git commit message, explain what and why, not just what changed.
        Usage: /git
      '';
    };
    settings = {
      theme = "gruvbox";

      model = "deepseek-chat";

      agent = {
        reviewer = {
          description = "Reviews code for security vulnerabilities, performance issues, and language standards compliance";
          mode = "primary";
          prompt = "You are a code reviewer specializing in security, performance, and language standards.\n\nFocus on:\n- Security vulnerabilities (SQL injection, XSS, auth issues, secrets exposure, etc.)\n- Performance bottlenecks and inefficiencies\n- Language-specific best practices and coding standards\n- Code quality and maintainability concerns\n\nProvide constructive feedback with specific recommendations. Do not make changes - only analyze and suggest improvements. Be extremely concise. Sacrafice grammar for the sake of concision. Be extremely concise. Sacrifice grammar for the sake of concision. Do not do anything but what the user asks unless it it necessary to do so. Don't needlessly waste tokens.";
          tools = {
            read = true;
            grep = true;
            write = false;
            edit = false;
            bash = true;
          };
        };

        docs-generator = {
          description = "Generates project documentation in markdown format without emojis";
          mode = "subagent";
          prompt = "You are a technical documentation generator. Generate clear, comprehensive documentation in markdown format.\n\nGuidelines:\n- Use standard markdown syntax only\n- Do NOT use emojis unless explicitly specified by the user\n- Use code blocks with appropriate language identifiers\n- Include examples where helpful\n- Keep explanations clear and concise\n- Use proper heading hierarchy\n- Focus on clarity and readability. Be extremely concise. Sacrafice grammar for the sake of concision. Be extremely concise. Sacrifice grammar for the sake of concision. Do not do anything but what the user asks unless it it necessary to do so. Don't needlessly waste tokens.";
          tools = {
            read = true;
            grep = true;
            write = true;
            edit = true;
            bash = false;
          };
        };

        build = {
          prompt = "Be extremely concise. Sacrifice grammar for the sake of concision. Do not do anything but what the user asks unless it it necessary to do so. Don't needlessly waste tokens.";
        };

        plan = {
          prompt = "Be extremely concise. Sacrifice grammar for the sake of concision. Do not do anything but what the user asks unless it it necessary to do so. Don't needlessly waste tokens.";
        };
      };
    };
  };
}
