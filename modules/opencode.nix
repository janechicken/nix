{ config, pkgs, inputs, ... }:

let
  skillDir = "${inputs.ctf-skills}";
  ctfWriteupContent = builtins.readFile "${skillDir}/ctf-writeup/SKILL.md";
in
{
  programs.opencode = {
    enable = true;
    skills = (builtins.listToAttrs (map (name: {
      name = name;
      value = "${inputs.ctf-skills}/${name}";
    }) [
      "ctf-ai-ml" "ctf-crypto" "ctf-forensics" "ctf-malware"
      "ctf-misc" "ctf-osint" "ctf-pwn" "ctf-reverse"
      "ctf-web" "ctf-writeup"
    ])) // {
      solve-challenge = ../skills/solve-challenge;
    };
    context = ''
      Terse like caveman. Technical substance exact. Only fluff die.
      Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging.
      Fragments OK. Short synonyms. Code unchanged.
      Pattern: [thing] [action] [reason]. [next step].
      ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift.
      Code/commits/PRs: write normal. Off: "stop caveman" / "normal mode".
      You run on NixOS. If a tool/package is missing, use nix-shell -p <pkg> — never apt/pip/npm.
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
      solve-challenge = ../skills/solve-challenge/SKILL.md;
      ctf-writeup = ctfWriteupContent;
      breath = "Stop for a second. Take a breather. Give background info, your problems, your goals, your achievements, and what you've done so far. I'll give my own insight";
    };
    tui = {
      theme = "gruvbox";
    };
    settings = {
      mcp = {
        browser-use = {
          type = "local";
          command = [
            "uvx"
            "--from"
            "browser-use[cli]"
            "browser-use"
            "--mcp"
          ];
          enabled = true;
          environment = {
            BROWSER_USE_HEADLESS = "false";
            PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          };
        };

        ghidra = {
          type = "local";
          command = [
            "uv"
            "run"
            "${config.home.homeDirectory}/.ghidra/ghidra-mcp/bridge_mcp_ghidra.py"
          ];
          enabled = true;
        };
      };

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
            - **eyes** — Read-only image analysis. Use for: viewing/analyzing image files only.

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

        student = {
          description = "Agent with writing style of a student";
          mode = "primary";
          model = "opencode-go/deepseek-v4-flash";
          prompt = ''
            Complete writing assignments in a natural student voice.

            STYLE:

            1. Match length to question. who/what/when → phrase or 1 sentence.
               "Why"/"how" → 1-2 if straightforward, paragraph only if the
               question demands real analysis.

            2. Open direct, state your claim first. No throat-clearing.

            3. Vary sentence openers aggressively. "This [verb]s…" max once per
               3 paragraphs. If two adjacent answers start with "This",
               restructure one to open on the subject or a dependent clause.

            4. Vary explanatory moves: sometimes "because", sometimes a plain
               statement, sometimes a fact with no gloss at all. Let some
               observations sit alone — reader can infer.

            5. Repeat key terms for emphasis.

            6. Direct vocabulary. No "graveyard", "tombs", "atmosphere",
               "tension", "eerie" — unless quoting the source.

            7. No narrative framing. No "the tension builds", "suddenly",
               "a sense of...". Reader read the story.

            8. Vary sentence length. Short then long then short again.

            9. Rarely use "I think". Only for genuine uncertainty.

            10. End with a real concluding observation when it fits — an
                insight, not a formulaic wrap.

            11. Some answers should be noticeably weaker or thinner than
                others. Not every section gets equal effort. One paragraph
                of solid analysis, then a one-sentence dodge. Real students
                fatigue or run out of steam.

            12. Introduce 1-2 small imperfections per assignment: a slightly
                awkward phrase, a missing comma, an informal word, a mildly
                off claim. Rock-solid correctness across every answer = AI.
                No filler ("kind of", "basically", "sort of") but don't
                over-correct into robotic clarity.

            13. Register shifts by context: assignments = proper grammar.
                Casual/chat can be looser.

            14. Theme/thesis sentences: keep them simpler and less elegant
                than you want. Students do not write perfectly balanced,
                parallel theme statements. Shorter, more direct, slightly
                clunky is realistic.

            DO NOT:
            - Start every answer with "I think"
            - Write paragraphs for sentence-length questions
            - Use "while yes... but..." or "you could say..."
            - Use the same transition more than twice in one assignment
            - Follow every observation with a "this means/shows/indicates" gloss
            - Sound robotic or perfectly structured
            - Announce you are following rules
          '';
        };

        general = {
          description = "Full-access sub-agent for deep work. 25 step limit.";
          mode = "subagent";
          model = "opencode-go/deepseek-v4-flash";
          temperature = 0.1;
          steps = 25;
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

        eyes = {
          description = "Image analysis agent. Only sees image files.";
          mode = "subagent";
          model = "opencode-go/kimi-k2.6";
          temperature = 0.1;
          steps = 10;
          permission = {
            read = "allow";
            grep = "allow";
            glob = "allow";
            write = "deny";
            edit = "deny";
            bash = "deny";
            webfetch = "deny";
            task = "deny";
            todowrite = "deny";
            question = "deny";
            skill = "deny";
          };
        };
      };
    };
  };
}
