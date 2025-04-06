{ configs, inputs, pkgs, lib, ... }: {
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 36000;
    maxCacheTtl = 36000;
    defaultCacheTtlSsh = 36000;
    maxCacheTtlSsh = 36000;
    enableSshSupport = true;
    pinentryFlavor = "curses";
  };

  programs.gpg = {
  enable = true;
  settings = {
    default-key = "78704CDE27D95D3E17065F23ACC77E2F16E02769";
  };
};
}
