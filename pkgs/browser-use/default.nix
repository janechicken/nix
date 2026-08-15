{
  lib,
  python,
  buildPythonPackage,
  fetchPypi,
  hatchling,
  makeWrapper,
  playwright-driver,
  aiohttp,
  anthropic,
  anyio,
  browser-use-sdk,
  bubus,
  cdp-use,
  click,
  cloudpickle,
  google-api-core,
  google-api-python-client,
  google-auth,
  google-auth-oauthlib,
  google-genai,
  groq,
  httpx,
  inquirerpy,
  markdownify,
  mcp,
  ollama,
  openai,
  pillow,
  posthog,
  psutil,
  pydantic,
  pyotp,
  pypdf,
  python-docx,
  python-dotenv,
  reportlab,
  requests,
  rich,
  screeninfo,
  typing-extensions,
  uuid7,
}:

buildPythonPackage rec {
  pname = "browser-use";
  version = "0.12.6";
  format = "pyproject";

  src = fetchPypi {
    pname = "browser_use";
    inherit version;
    sha256 = "2c920f8120741334ed630e9ddc360bb5e20c40449ea2adfa81dc8e7d9f5b4d94";
  };

  nativeBuildInputs = [
    hatchling
    makeWrapper
  ];

  makeWrapperArgs = [
    "--set"
    "PLAYWRIGHT_BROWSERS_PATH"
    "${playwright-driver.browsers}"
  ];

  propagatedBuildInputs = [
    aiohttp
    anthropic
    anyio
    browser-use-sdk
    bubus
    cdp-use
    click
    cloudpickle
    google-api-core
    google-api-python-client
    google-auth
    google-auth-oauthlib
    google-genai
    groq
    httpx
    inquirerpy
    markdownify
    mcp
    ollama
    openai
    pillow
    posthog
    psutil
    pydantic
    pyotp
    pypdf
    python-docx
    python-dotenv
    reportlab
    requests
    rich
    screeninfo
    typing-extensions
    uuid7
  ];

  doCheck = false;
  dontCheckRuntimeDeps = true;
  pythonImportsCheck = [ "browser_use" ];

  postPatch = ''
    ${python.interpreter} << 'EOF'
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

  meta = with lib; {
    description = "Make websites accessible for AI agents";
    homepage = "https://github.com/browser-use/browser-use";
    license = licenses.mit;
  };
}
