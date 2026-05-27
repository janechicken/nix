{ pkgs, ... }:
{
  xdg.configFile."mcp/mcp.json" = {
    text = builtins.toJSON {
      mcpServers = {
        browser-use = {
          command = "uvx";
          args = [
            "--from"
            "browser-use[cli]"
            "browser-use"
            "--mcp"
          ];
          env = {
            BROWSER_USE_HEADLESS = "false";
            PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          };
        };
        ghidra = {
          command = "${pkgs.ghidra-mcp}/bin/ghidra-mcp";
          args = [ ];
        };
      };
    };
  };
}
