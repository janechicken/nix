final: prev: {
  # Snapdragon X2 Plus (Mahua / X2P-42-100) kernel for Lenovo Yoga Slim 7 14Q8Y11 (83QR).
  # Built from torvalds/linux 7.4-rc3 + 6 upstream qcom fixes + Mahua GPU/GMU +
  # hardware-verified 14Q8Y11 board DTS + Bjorn Andersson's v8 eDP PHY 2-lane/5.4Gbps fix.
  linuxPackages_mahua = final.linuxKernel.packagesFor (
    final.callPackage ../pkgs/linux-mahua {
      kernelPatches = [ ];
    }
  );

  # Add ALSA UCM2 profile for Lenovo Yoga Slim 7 14Q8Y11 (2x WSA8845 speakers,
  # 2x VA DMICs, 2x DisplayPort audio sinks) matching Lenovo-Yoga-Slim7-14Q8Y11-tplg.bin.
  #
  # UCM2 verb-file lookup (ucm2/ucm.conf, Define.V2ConfD block) probes, in order:
  #   ucm2/conf.d/${CardDriver}/${CardLongName}.conf
  #   ucm2/conf.d/${CardDriver}/${CardDriver}.conf
  # where CardDriver/CardLongName come from the live card. For this board
  # (verified with `strace alsaucm -c hw:0 list _verbs`):
  #   CardDriver   = "glymur"                                 (/proc/asound/cards: "glymur - Lenovo-Yoga-Slim7-14Q8Y11")
  #   CardLongName = "LENOVO-83QR-YogaSlim714Q8Y11-LNVNB161216"
  # so the file that is actually opened is
  #   conf.d/glymur/LENOVO-83QR-YogaSlim714Q8Y11-LNVNB161216.conf
  # NOT conf.d/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf (that is the card *name*,
  # only used by the legacy UCM v1/V2Name lookups, which are disabled).
  alsa-ucm-conf-mahua = prev.alsa-ucm-conf.overrideAttrs (old: {
    # The two UCM2 files live as real, tracked files in pkgs/alsa-ucm-conf-mahua/
    # (not as heredocs inside a Nix string: nixfmt-rfc-style re-indents
    # multi-line strings, which would silently push the `EOF` delimiter off
    # column 0 and break the script, and the `${CardId}` placeholders would
    # need `''${...}` escaping).
    postInstall = (old.postInstall or "") + ''
      ucm2=$out/share/alsa/ucm2

      install -Dm644 ${../pkgs/alsa-ucm-conf-mahua/Lenovo-Yoga-Slim7-14Q8Y11.conf} \
        $ucm2/Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf
      install -Dm644 ${../pkgs/alsa-ucm-conf-mahua/Lenovo-Yoga-Slim7-14Q8Y11-HiFi.conf} \
        $ucm2/Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11-HiFi.conf
      mkdir -p $ucm2/conf.d/glymur $ucm2/conf.d/x1e80100

      # The long-name symlink in conf.d/glymur/ is the one UCM2 actually probes
      # for this card (see the CardDriver/CardLongName note above); without it
      # `alsaucm -c hw:0` fails with "failed to import hw:0 use case
      # configuration -2" and PipeWire exposes the card with zero sinks/sources.
      ln -sf ../../Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf \
        $ucm2/conf.d/glymur/LENOVO-83QR-YogaSlim714Q8Y11-LNVNB161216.conf

      # Kept for the legacy UCM v1 / V2Name lookups (card name, not long name).
      ln -sf ../../Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf \
        $ucm2/conf.d/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf

      # Harmless fallback: only used if the machine driver's card->driver ever
      # stops being "glymur" and becomes "x1e80100" (the snd_soc_x1e80100
      # driver name reported by PipeWire as alsa.driver_name).
      ln -sf ../../Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf \
        $ucm2/conf.d/x1e80100/LENOVO-83QR-YogaSlim714Q8Y11-LNVNB161216.conf
    '';
  });
}
