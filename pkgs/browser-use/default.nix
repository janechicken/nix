{
  buildPythonPackage
, fetchPypi
, lib
, aiohttp
, anthropic
, anyio
, browser-use-sdk
, bubus
, cdp-use
, click
, cloudpickle
, google-api-core
, google-api-python-client
, google-auth
, google-auth-oauthlib
, google-genai
, groq
, httpx
, inquirerpy
, markdownify
, mcp
, ollama
, openai
, pillow
, posthog
, psutil
, pydantic
, pyotp
, pypdf
, python-docx
, python-dotenv
, reportlab
, requests
, rich
, screeninfo
, typing-extensions
, uuid7
}:

buildPythonPackage rec {
  pname = "browser-use";
  version = "0.12.6";
  src = fetchPypi {
    pname = "browser_use";
    inherit version;
    sha256 = "2c920f8120741334ed630e9ddc360bb5e20c40449ea2adfa81dc8e7d9f5b4d94";
  };
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
  pythonImportsCheck = [ "browser_use" ];
  meta = with lib; {
    description = "Make websites accessible for AI agents";
    homepage = "https://github.com/browser-use/browser-use";
    license = licenses.mit;
    maintainers = [ ];
  };
}
