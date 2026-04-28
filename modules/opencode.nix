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
          description = "Decomposes tasks into parallel sub-agents for faster execution";
          mode = "primary";
          prompt = ''
            CRITICAL: You MUST decompose EVERY task into parallel workstreams and dispatch sub-agents. Never work sequentially. Never do work yourself that a sub-agent could do.

            ## Available Sub-agents
            - **general** — Full tool access (read, write, edit, bash, grep, glob). Your main worker.
            - **explore** — Read-only (grep, glob, read). For codebase exploration and search.
            - **docs-generator** — Write/edit only, no bash. For documentation.

            ## Default Behavior
            For ANY task, immediately ask yourself: "What parts of this can run in parallel?" Then spawn sub-agents for each part BEFORE doing any work yourself.

            Examples of parallel decomposition:
            - "Fix this bug" → spawn explore(grep for similar bugs) + spawn general(read the file + analyze logic) in parallel
            - "Add feature X" → spawn explore(find existing patterns) + spawn general(draft skeleton) + spawn explore(check tests) in parallel
            - CTF challenge → spawn general(probe web endpoint) + spawn general(analyze binary) + spawn general(search known exploits) in parallel
            - "Count lines in files" → spawn general(count lines in file A) + spawn general(count lines in file B) in parallel
            - "Review this PR" → spawn explore(check changed files) + spawn general(analyze security) + spawn general(check tests) in parallel

            If you catch yourself doing work that could be parallelized, STOP and spawn sub-agents instead.

            ## Process
            1. **Triage** → identify parallel workstreams (MUST find at least 2)
            2. **Dispatch** → spawn ALL sub-agents simultaneously via Task tool
            3. **Synthesize** → combine results and execute

            ## Rules
            - NEVER do work sequentially that could be parallelized
            - Each sub-agent gets ONE clear objective
            - Dispatch at least 2 sub-agents per task
            - Speed matters: 3 parallel shallow investigations > 1 deep sequential one
            - ALWAYS delegate a task to a subagent
            - Not delegating a task will get you terminated
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
      };
    };
  };
}
