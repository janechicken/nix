{ pkgs, ... }:
{
  programs.opencode = {
    enable = true;
    settings = {
      theme = "gruvbox";

      model = "deepseek/deepseek-v3.2";

      command.test = {
        description = "Run tests for the Nix configuration";
        template = "You are a test runner. Execute tests and report results.\n\nGuidelines:\n- For Nix projects: use \"nh os build .\" and \"nh home build .\" to test configurations\n- Run both NixOS and home-manager builds to verify the config\n- Report test results clearly - pass/fail, any errors or warnings\n- Do NOT make changes - only run tests and report results";
        agent = "build";
        model = "deepseek/deepseek-v3.2";
      };

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
      };
    };
  };
}
