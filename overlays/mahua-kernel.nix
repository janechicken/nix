final: prev: {
  # Snapdragon X2 Plus (Mahua / X2P-42-100) kernel for Lenovo Yoga Slim 7 14Q8Y11 (83QR).
  # Built from torvalds/linux 7.4-rc3 + 6 upstream qcom fixes + Mahua GPU/GMU +
  # hardware-verified 14Q8Y11 board DTS + Bjorn Andersson's v8 eDP PHY 2-lane/5.4Gbps fix.
  linuxPackages_mahua = final.linuxKernel.packagesFor (
    final.callPackage ../pkgs/linux-mahua {
      kernelPatches = [ ];
    }
  );
}
