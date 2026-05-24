{ config, pkgs, lib, ... }:

let
  cfg = config.programs.comfyui;
in
{
  options.programs.comfyui = {
    enable = lib.mkEnableOption "ComfyUI (node-based image generation on Intel Arc)";

    syclDeviceFilter = lib.mkOption {
      type = lib.types.str;
      default = "opencl:gpu";
      description = "SYCL device filter for Intel Arc GPU. 'opencl:gpu' or 'level_zero:gpu'.";
    };

    modelsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/ComfyUI/models";
      description = "Directory for ComfyUI models (checkpoints, LoRAs, VAE, etc).";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      git
      python311
      python311Packages.pip
      uv
      (pkgs.writeShellScriptBin "comfyui" ''
        set -e
        BASEDIR="$HOME/ComfyUI"
        REPO="$BASEDIR/repo"
        VENV="$BASEDIR/venv"
        MODELS="$BASEDIR/models"

        echo "ComfyUI — jane-pc (Arc A750)"
        echo ""

        # Clone if missing
        if [ ! -d "$REPO/.git" ]; then
          echo "First run — cloning ComfyUI to $REPO..."
          mkdir -p "$BASEDIR"
          ${pkgs.git}/bin/git clone https://github.com/comfyanonymous/ComfyUI "$REPO"
          mkdir -p "$MODELS"/{checkpoints,loras,vae,controlnet,upscale_models,embeddings}
          ln -sfn "$MODELS" "$REPO/models"
          echo "Model directories created:"
          echo "  $MODELS/checkpoints/  — main model files (.safetensors)"
          echo "  $MODELS/loras/        — LoRAs / LyCORIS"
          echo "  $MODELS/vae/          — VAE models"
          echo "  $MODELS/controlnet/   — ControlNet models"
          echo "  $MODELS/upscale_models/ — upscalers"
        fi

        # Create venv if missing
        if [ ! -d "$VENV" ]; then
          echo "Creating Python venv..."
          ${pkgs.python311}/bin/python -m venv "$VENV"
        fi

        source "$VENV/bin/activate"

        # Install deps if not done yet
        if [ ! -f "$REPO/.deps_installed" ]; then
          echo "Installing Python deps (one-time, takes a few minutes)..."
          pip install --upgrade pip -q
          pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu -q
          pip install intel-extension-for-pytorch -q
          pip install -r "$REPO/requirements.txt" -q
          touch "$REPO/.deps_installed"
          echo ""
          echo "Done. Download a model to get started:"
          echo "  wget -P $MODELS/checkpoints https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
          echo ""
          echo "Run 'comfyui' again to start the server."
          exit 0
        fi

        echo "Starting on http://127.0.0.1:8188 ..."
        export SYCL_DEVICE_FILTER="${cfg.syclDeviceFilter}"
        cd "$REPO"
        exec python main.py --force-fp16
      '')
    ];

    home.sessionVariables = {
      SYCL_DEVICE_FILTER = cfg.syclDeviceFilter;
    };
  };
}
