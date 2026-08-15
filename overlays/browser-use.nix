final: prev: {
  # Add only the packages nixpkgs does not already provide. Overriding
  # python312 itself (packageOverrides) makes a new interpreter and forces a
  # full python3.12-* rebuild (scipy, django, …) instead of using Hydra.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (
      pyfinal: pyprev:
      let
        # nativeCheckInputs stay in the drv even when doCheck = false, so
        # python-docx still pulled in behave (and behave's test suite).
        # Only strip them on 3.12 (browser-use). Doing this on 3.14 would
        # rebuild ghidra-mcp's python env.
        isPy312 = pyprev.python.pythonVersion == "3.12";
        skipCheck =
          pkg:
          pkg.overrideAttrs (_: {
            doCheck = false;
            checkInputs = [ ];
            nativeCheckInputs = [ ];
            installCheckInputs = [ ];
            nativeInstallCheckInputs = [ ];
          });
        maybeSkip = pkg: if isPy312 then skipCheck pkg else pkg;
      in
      {
        uuid7 = pyfinal.callPackage ../pkgs/browser-use/uuid7.nix { };
        browser-use-sdk = pyfinal.callPackage ../pkgs/browser-use/browser-use-sdk.nix { };
        cdp-use = pyfinal.callPackage ../pkgs/browser-use/cdp-use.nix { };
        bubus = pyfinal.callPackage ../pkgs/browser-use/bubus.nix { };
        agentmail = pyfinal.callPackage ../pkgs/browser-use/agentmail.nix { };
        browser-use = pyfinal.callPackage ../pkgs/browser-use {
          inherit (final) playwright-driver;
        };

        python-docx = maybeSkip pyprev.python-docx;
        mcp = maybeSkip pyprev.mcp;
        fastapi = maybeSkip pyprev.fastapi;
        anthropic = maybeSkip pyprev.anthropic;
        openai = maybeSkip pyprev.openai;
        groq = maybeSkip pyprev.groq;
        google-genai = maybeSkip pyprev.google-genai;
        ollama = maybeSkip pyprev.ollama;
        posthog = maybeSkip pyprev.posthog;
        google-api-python-client = maybeSkip pyprev.google-api-python-client;
        google-auth-oauthlib = maybeSkip pyprev.google-auth-oauthlib;
      }
    )
  ];

  browser-use = final.python312Packages.browser-use;
}
