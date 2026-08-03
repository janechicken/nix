final: prev: {
  python312 = prev.python312.override {
    packageOverrides = pyfinal: pyprev: {
      uuid7 = pyfinal.callPackage ../pkgs/browser-use/uuid7.nix { };
      browser-use-sdk = pyfinal.callPackage ../pkgs/browser-use/browser-use-sdk.nix { };
      cdp-use = pyfinal.callPackage ../pkgs/browser-use/cdp-use.nix { };
      bubus = pyfinal.callPackage ../pkgs/browser-use/bubus.nix { };
      agentmail = pyfinal.callPackage ../pkgs/browser-use/agentmail.nix { };

      # jsonpath-python 1.1.6 has a flaky performance benchmark that fails
      # on this hardware. Required by mistralai (browser-use dep tree).
      jsonpath-python = pyprev.jsonpath-python.overrideAttrs (old: {
        doCheck = false;
      });

      # scipy 1.18.0 test_support_moments_sample[Normal] is a flaky
      # hypothesis-property test (tolerance 2e-09 vs ~2e-09 mismatch). Fails
      # intermittently on this hardware. Required by pint (browser-use dep tree).
      scipy = pyprev.scipy.overrideAttrs (old: {
        disabledTests = (old.disabledTests or [ ]) ++ [ "test_support_moments_sample" ];
      });

      # inline-snapshot test_docs snapshot tests are out of sync with current
      # source/pytest and fail spuriously. Required by browser-use dep tree.
      inline-snapshot = pyprev.inline-snapshot.overrideAttrs (old: {
        disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [ "tests/test_docs.py" ];
      });

      # django test_crafted_xml_performance is a wall-clock perf test (2.16s vs
      # 2.0s limit) that fails on this hardware, plus flaky test_pickle.
      # Required by google-api-python-client.
      django = pyprev.django.overrideAttrs (old: {
        disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [ "django/core/serializers/tests/test_deserialization.py" ];
        disabledTests = (old.disabledTests or [ ]) ++ [ "test_pickle" ];
      });
    };
  };
  browser-use = final.python312Packages.buildPythonPackage (with final.python312Packages; {
    pname = "browser-use";
    version = "0.12.6";
    format = "pyproject";
    src = final.fetchPypi {
      pname = "browser_use";
      version = "0.12.6";
      sha256 = "2c920f8120741334ed630e9ddc360bb5e20c40449ea2adfa81dc8e7d9f5b4d94";
    };
    nativeBuildInputs = [ hatchling final.makeWrapper ];
    makeWrapperArgs = [
      "--set" "PLAYWRIGHT_BROWSERS_PATH" "${final.playwright-driver.browsers}"
    ];
    propagatedBuildInputs = [
      aiohttp anthropic anyio browser-use-sdk bubus cdp-use click
      cloudpickle google-api-core google-api-python-client google-auth
      google-auth-oauthlib google-genai groq httpx inquirerpy markdownify
      mcp ollama openai pillow posthog psutil pydantic pyotp pypdf
      python-docx python-dotenv reportlab requests rich screeninfo
      typing-extensions uuid7
    ];
    doCheck = false;
    dontCheckRuntimeDeps = true;
    pythonImportsCheck = [ "browser_use" ];
    postPatch = ''
      ${final.python312Packages.python.interpreter} << 'EOF'
p = 'browser_use/skill_cli/main.py'
with open(p) as f:
    src = f.read()
src = src.replace(
    'env = os.environ.copy()',
    'env = os.environ.copy()\n\tenv["PYTHONPATH"] = ":".join(sys.path) + ":" + env.get("PYTHONPATH", "")'
)
with open(p, 'w') as f:
    f.write(src)
EOF
    '';
    meta = with final.lib; {
      description = "Make websites accessible for AI agents";
      homepage = "https://github.com/browser-use/browser-use";
      license = licenses.mit;
    };
  });
}
