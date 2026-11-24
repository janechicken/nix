# Mesa for the Adreno X2-45 (Snapdragon X2 Plus / Mahua) in the Lenovo Yoga
# Slim 7 14Q8Y11 (83QR).
#
# Scoped on purpose: this is wired in only through
# `hardware.graphics.package` on the `yogabook` host. It must never be applied
# as a `mesa` overlay, because changing `pkgs.mesa` invalidates
# cache.nixos.org for every GUI package in the closure (Qt/GTK/Hyprland/...).
#
# The freedreno driver set is trimmed to what this machine can actually use, so
# the laptop does not compile the AMD/Intel/NVIDIA/Broadcom/Apple/Panfrost
# drivers just to add one GPU id. `llvmpipe` (gallium) and `swrast` (vulkan)
# stay for software fallback and for zink/llvmpipe-hook consumers.
{
  lib,
  mesa,
}:

let
  # Trimmed driver set. mesa.override re-calls the nixpkgs mesa derivation with
  # different meson -Dgallium-drivers/-Dvulkan-drivers values.
  trimmed = mesa.override {
    galliumDrivers = [
      "freedreno"
      "llvmpipe"
      "zink"
      "virgl"
    ];
    vulkanDrivers = [
      "freedreno"
      "swrast"
    ];
  };
in
trimmed.overrideAttrs (old: {
  pname = "${old.pname}-mahua";
  patches = (old.patches or [ ]) ++ [ ./0001-freedreno-add-adreno-x2-45.patch ];
})
