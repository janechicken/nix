{ config, pkgs, lib, inputs, ... }: {
  # ===========================================================================
  # oh-my-pi (omp) — coding agent with the IDE wired in.
  #
  # Replaces the previous pi (pi-mono) install. omp is a fork distributed as
  # a self-contained binary. User config lives under ~/.omp/agent (YAML),
  # not ~/.pi/agent (JSON). Config files are tracked as dotfiles
  # (dotfiles/.omp/agent/*) and wired here — same pattern as awesome/rofi/zed.
  #
  # Build: package in pkgs/omp (overlay overlays/omp.nix) — fetches the
  # v18.0.10 linux-x64/arm64 release asset, patchelf'd with dontStrip (stripping
  # breaks the embedded Bun runtime) for the glibc loader.
  #
  # Provider/model note: prior config used nanogpt + cheapcompute via pi
  # extensions. omp registers custom providers declaratively via models.yml
  # (~/.omp/agent/models.yml) — no extension needed. Both read their API keys
  # from sops-nix sessionVariables (NANOGPT_API_KEY, CHEAPCOMPUTE_API_KEY).
  # ===========================================================================

  home.file = {
    # --- custom providers (nanogpt + cheapcompute) --------------------------
    ".omp/agent/models.yml" = {
      force = true;
      source = ../dotfiles/.omp/agent/models.yml;
    };

    # --- custom theme (ported from pi autumn-dark, omp adds statusLine*) -----
    ".omp/agent/themes/autumn-dark.json" = {
      force = true;
      source = ../dotfiles/.omp/agent/themes/autumn-dark.json;
    };

    # --- Merge Gateway extension --------------------------------------------
    ".omp/agent/extensions/merge-gateway/package.json" = {
      force = true;
      source = ../dotfiles/.omp/agent/extensions/merge-gateway/package.json;
    };
    ".omp/agent/extensions/merge-gateway/index.ts" = {
      force = true;
      source = ../dotfiles/.omp/agent/extensions/merge-gateway/index.ts;
    };
  };

  home.packages = [ pkgs.omp ];

  # Seed a writable ~/.omp/agent/config.yml only if none exists yet. omp owns
  # this file afterwards (its setup wizard + /model etc. persist to it, e.g.
  # setupVersion, theme/model picks), so it must be a writable regular file,
  # NOT a read-only nix-store symlink (store symlinks make the setup wizard
  # repeat forever — it can't persist setupVersion). We therefore copy the
  # tracked dotfile seed into place on first run; the vision model there is
  # the qwen model the removed eyes subagent used.
  home.activation.writeOmpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p $HOME/.omp/agent
    # Replace any store symlink (read-only) and seed on first run. Keep a real
    # writable file the user (or omp itself) may have already configured.
    if [ -L $HOME/.omp/agent/config.yml ] || [ ! -f $HOME/.omp/agent/config.yml ]; then
      rm -f $HOME/.omp/agent/config.yml
      cp ${../dotfiles/.omp/agent/config.yml} $HOME/.omp/agent/config.yml
      chmod 600 $HOME/.omp/agent/config.yml
    fi
  '';
}
