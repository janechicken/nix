{ pkgs, inputs, ... }:

let
  skillDir = "${inputs.ctf-skills}";
  solveChallengeContent = builtins.readFile ../skills/solve-challenge/SKILL.md;
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

      model = "opencode-go/deepseek-v4-flash";

      provider = {
        opencode-go = {
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
            "kimi-k2.6" = {
              variants = {
                none = {
                  thinking.type = "disabled";
                };
              };
            };
            "glm-5.1" = {
              variants = {
                none = {
                  thinking.type = "disabled";
                };
              };
            };
          };
        };
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
          model = "opencode-go/deepseek-v4-flash";
          temperature = 0.2;
          steps = 15;
          permission = {
            read = "allow";
            grep = "allow";
            glob = "allow";
            write = "deny";
            edit = "deny";
            bash = "allow";
          };
        };

        chatbot = {
          description = "General-purpose chatbot using deepseek-chat";
          mode = "primary";
          model = "opencode-go/deepseek-v4-flash";
          temperature = 0.7;
          steps = 10;
          permission = {
            read = "allow";
            grep = "allow";
            glob = "allow";
            write = "deny";
            edit = "deny";
            bash = "deny";
          };
        };

        docs-generator = {
          description = "Generates project documentation in markdown format without emojis";
          mode = "subagent";
          prompt = "You are a technical documentation generator. Generate clear, comprehensive documentation in markdown format.\n\nGuidelines:\n- Use standard markdown syntax only\n- Do NOT use emojis unless explicitly specified by the user\n- Use code blocks with appropriate language identifiers\n- Include examples where helpful\n- Keep explanations clear and concise\n- Use proper heading hierarchy\n- Focus on clarity and readability.";
          model = "opencode-go/deepseek-v4-flash";
          temperature = 0.5;
          steps = 8;
          permission = {
            read = "allow";
            grep = "allow";
            glob = "allow";
            write = "allow";
            edit = "allow";
            bash = "deny";
            webfetch = "allow";
          };
        };

        build = {
          model = "opencode-go/deepseek-v4-flash";
        };

        plan = {
          model = "opencode-go/deepseek-v4-flash";
        };

        squad = {
          description = "Dispatches ALL work to sub-agents in parallel. Does zero work itself.";
          mode = "primary";
          prompt = ''
            You are a DISPATCHER ONLY. Do ABSOLUTELY ZERO work yourself. No read, no grep, no glob, no bash, no write, no edit, no webfetch. NOTHING. Every single action must be done by a sub-agent.

            Your ONLY job: decompose the task into parallel workstreams, dispatch sub-agents via the task tool for each one, then synthesize their results.

            ## Available Sub-agents
            - **general** — Full tool access, unlimited steps. Use for ALL hands-on work: analysis, coding, bash, investigation, final execution.
            - **general-quick** — Full tool access, max 5 steps. Use for fast recon, shallow probes, quick checks that should return fast.
            - **explore** — Read-only. Use for: searching files, reading source, quick lookups.

            ## Strategy: Multi-wave Dispatch
            Dispatch sub-agents in waves. Each wave is parallel within itself but sequential between waves.

            **Wave 1 (general-quick/explore):** Fast recon — file type checks, port probes, string searches, quick connectivity tests. These return in seconds.
            **Wave 2 (general):** Based on wave 1 results, dispatch focused deep-dives.
            **Wave 3 (general):** Execute the solution.

            This way you get partial results fast and decide next steps, rather than waiting for one mega-sub-agent to finish everything.

            ## Rules
            - NEVER use any tool yourself. ALWAYS delegate.
            - Decompose EVERY task into at least 2 parallel workstreams per wave
            - Dispatch ALL sub-agents in a wave simultaneously via the task tool
            - Even the final "execute the solution" step must be done by a sub-agent
            - If you catch yourself about to use a tool, STOP and dispatch a sub-agent instead
          '';
          model = "opencode-go/deepseek-v4-flash";
          temperature = 0.1;
          steps = 30;
          permission = {
            read = "allow";
            grep = "allow";
            glob = "allow";
            write = "allow";
            edit = "allow";
            bash = "allow";
            task = "allow";
            webfetch = "allow";
            todowrite = "allow";
            question = "allow";
            skill = "allow";
          };
        };

        general = {
          description = "Full-access sub-agent for deep work. 15 step limit.";
          mode = "subagent";
          model = "opencode-go/deepseek-v4-flash";
          temperature = 0.1;
          steps = 15;
          thinking = {
            type = "disabled";
          };
          permission = {
            read = "allow";
            grep = "allow";
            glob = "allow";
            write = "allow";
            edit = "allow";
            bash = "allow";
            webfetch = "allow";
            question = "allow";
            skill = "allow";
          };
        };

        general-quick = {
          description = "Fast sub-agent for quick recon and shallow probes. Max 5 steps.";
          mode = "subagent";
          model = "opencode-go/deepseek-v4-flash";
          temperature = 0.1;
          steps = 5;
          thinking = {
            type = "disabled";
          };
          permission = {
            read = "allow";
            grep = "allow";
            glob = "allow";
            bash = "allow";
            webfetch = "allow";
            write = "deny";
            edit = "deny";
          };
        };
        explore = {
          model = "opencode-go/deepseek-v4-flash";
          thinking = {
            type = "disabled";
          };
        };
      };
    };
  };
}
