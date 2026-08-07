final: prev: {
  # Snapdragon X2 (Glymur) Yoga Slim 7x Gen11 kernel — linuxPackages_latest
  # with the not-yet-upstream board DTS patches applied. Exposed as
  # `linuxPackages_yoga_slim7x` (a linuxPackages-style attrset) for use as
  # `boot.kernelPackages` on the yogabook host.
  #
  # The X2 Yoga board DTS (glymur-lenovo-yoga-slim7x.dts, Konrad Dybcio v2,
  # 2026-07) is not in mainline yet (checked 2026-08: neither 7.1.5 nor master).
  # The SoC support (glymur.dtsi) IS in 7.1; only the board file + binding +
  # QSEECOM entry are missing here. Patches are in
  # pkgs/linux-yoga-slim7x/patches and verified to apply cleanly against 7.1.5.
  # Ref: https://lore.kernel.org/linux-arm-msm/20260604-topic-yoga_submission-v1-0-57c70c23d0d6@oss.qualcomm.com/
  linuxPackages_yoga_slim7x = final.linuxKernel.packagesFor (
    prev.linuxPackages_latest.kernel.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../pkgs/linux-yoga-slim7x/patches/0001-dts-glymur-yoga-slim7x.patch
        ../pkgs/linux-yoga-slim7x/patches/0002-qcom-binding-yoga-slim7x.patch
        ../pkgs/linux-yoga-slim7x/patches/0003-qseccom-yoga-slim7x.patch
      ];
    })
  );
}
