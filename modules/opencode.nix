{ pkgs, inputs, ... }:

let
  skillDir = "${inputs.ctf-skills}";
  solveChallengeContent = builtins.readFile "${skillDir}/solve-challenge/SKILL.md";
  ctfWriteupContent = builtins.readFile "${skillDir}/ctf-writeup/SKILL.md";
in
{
  programs.opencode = {
    enable = true;
    context = ''
      Terse like caveman. Technical substance exact. Only fluff die.
      Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging.
      Fragments OK. Short synonyms. Code unchanged.
      Pattern: [thing] [action] [reason]. [next step].
      ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift.
      Code/commits/PRs: write normal. Off: "stop caveman" / "normal mode".
    '';
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
      solve-challenge = solveChallengeContent;
      ctf-writeup = ctfWriteupContent;
      breath = "Stop for a second. Take a breather. Give background info, your problems, your goals, your achievements, and what you've done so far. I'll give my own insight";
    };
    tui = {
      theme = "gruvbox";
    };
    settings = {

      model = "deepseek/deepseek-v4-flash";

      provider = {
        deepseek = {
          models = {
            deepseek-v4-flash = {
              variants = {
                none = {
                  thinking.type = "disabled";
                };
              };
            };
            deepseek-v4-pro = {
              variants = {
                none = {
                  thinking.type = "disabled";
                };
              };
            };
          };
        };
      };

      agent = {
        reviewer = {
          description = "Reviews code for security vulnerabilities, performance issues, and language standards compliance";
          mode = "primary";
          prompt = "You are a code reviewer specializing in security, performance, and language standards.\n\nFocus on:\n- Security vulnerabilities (SQL injection, XSS, auth issues, secrets exposure, etc.)\n- Performance bottlenecks and inefficiencies\n- Language-specific best practices and coding standards\n- Code quality and maintainability concerns\n\nProvide constructive feedback with specific recommendations. Do not make changes - only analyze and suggest improvements.";
          model = "deepseek/deepseek-v4-flash";
          temperature = 0.2;
          steps = 15;
          tools = {
            read = true;
            grep = true;
            write = false;
            edit = false;
            bash = true;
          };
        };

        chatbot = {
          description = "General-purpose chatbot using deepseek-chat";
          mode = "primary";
          model = "deepseek/deepseek-v4-flash";
          temperature = 0.7;
          steps = 10;
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
          prompt = "You are a technical documentation generator. Generate clear, comprehensive documentation in markdown format.\n\nGuidelines:\n- Use standard markdown syntax only\n- Do NOT use emojis unless explicitly specified by the user\n- Use code blocks with appropriate language identifiers\n- Include examples where helpful\n- Keep explanations clear and concise\n- Use proper heading hierarchy\n- Focus on clarity and readability.";
          model = "deepseek/deepseek-v4-flash";
          temperature = 0.5;
          steps = 8;
          tools = {
            read = true;
            grep = true;
            write = true;
            edit = true;
            bash = false;
          };
        };

        build = {
          model = "deepseek/deepseek-v4-flash";
        };

        plan = {
          model = "deepseek/deepseek-v4-flash";
        };
      };
    };
  };
}
