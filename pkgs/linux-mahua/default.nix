{
  lib,
  buildLinux,
  fetchurl,
  ...
}@args:

buildLinux (
  args
  // {
    version = "7.4.0-rc3";
    modDirVersion = "7.4.0-rc3";
    extraMeta.branch = "7.4";

    # Upstream torvalds/linux 7.4-rc3 base commit verified on Lenovo Yoga Slim 7 14Q8Y11
    src = fetchurl {
      url = "https://github.com/torvalds/linux/archive/7b7fe306dd86b5342d3be8a3f1cbf3bb1ebf280f.tar.gz";
      hash = "sha256-5IlZflCVJs2MeDCts4ZvxWWKCVXc6Ll/rKZfPwuSogA=";
    };

    kernelPatches = (args.kernelPatches or [ ]) ++ [
      {
        name = "clk-qcom-gcc-glymur-critical-clocks";
        patch = ./patches/0001-clk-qcom-gcc-glymur-Mark-GCC-AV1E-AHB-and-XO-clocks-.patch;
      }
      {
        name = "clk-qcom-gcc-pcie-pipe-force-mem-core";
        patch = ./patches/0002-clk-qcom-gcc-Set-FORCE_MEM_CORE_ON-FORCE_PERIPH_CORE.patch;
      }
      {
        name = "dts-qcom-glymur-adsp-remote-heap-no-map";
        patch = ./patches/0003-arm64-dts-qcom-glymur-Make-the-ADSP-remote-heap-no-m.patch;
      }
      {
        name = "dts-qcom-glymur-cdsp-fastrpc-cb-reg";
        patch = ./patches/0004-arm64-dts-qcom-glymur-Fix-fastrpc-compute-cb-reg-val.patch;
      }
      {
        name = "soc-qcom-cmd-db-probe-race";
        patch = ./patches/0005-soc-qcom-cmd-db-Fix-probe-race-with-possible-ERR_PTR.patch;
      }
      {
        name = "soc-qcom-pmic-glink-altmode-uaf";
        patch = ./patches/0006-soc-qcom-pmic_glink_altmode-Fix-use-after-free-of-wo.patch;
      }
      {
        name = "dts-qcom-mahua-gpu-gmu";
        patch = ./patches/0007-arm64-dts-qcom-mahua-Support-GPU-and-GMU.patch;
      }
      {
        name = "dts-qcom-mahua-lenovo-yoga-slim7-14q8y11";
        patch = ./patches/0008-arm64-dts-qcom-mahua-lenovo-yoga-slim7-14q8y11.patch;
      }
      {
        name = "phy-qcom-edp-split-power-on-by-version";
        patch = ./patches/0009-phy-qcom-edp-split-power-on-by-version.patch;
      }
      {
        name = "phy-qcom-edp-update-v8-power-on-sequence";
        patch = ./patches/0010-phy-qcom-edp-update-v8-power-on-sequence.patch;
      }
    ];

    # Allow 7.4-rc3 Kconfig differences against nixpkgs common-config.nix
    ignoreConfigErrors = true;

    structuredExtraConfig = with lib.kernel; {
      # Core Snapdragon X2 Plus (Mahua / Glymur) SoC
      ARCH_QCOM = yes;
      CLK_GLYMUR_GCC = yes;
      CLK_GLYMUR_TCSRCC = yes;
      CLK_GLYMUR_DISPCC = yes;
      CLK_GLYMUR_GPUCC = yes;
      PINCTRL_GLYMUR = yes;
      PINCTRL_QCOM_SPMI_PMIC = yes;
      PINCTRL_LPASS_LPI = module;
      PINCTRL_SM8650_LPASS_LPI = module;
      INTERCONNECT_QCOM_GLYMUR = yes;
      QCOM_RPMH = yes;
      QCOM_RPMHPD = yes;
      QCOM_CLK_RPMH = yes;
      REGULATOR_QCOM_RPMH = yes;
      QCOM_PDC = yes;
      RESET_QCOM_PDC = yes;
      QCOM_AOSS_QMP = yes;
      QCOM_CPUCP_MBOX = yes;
      SPMI_MSM_PMIC_ARB = yes;
      MFD_SPMI_PMIC = yes;
      QCOM_GPI_DMA = yes;
      QCOM_TSENS = yes;
      QCOM_LMH = yes;
      NVMEM_QCOM_QFPROM = yes;
      ARM_QCOM_CPUFREQ_NVMEM = yes;

      # PCIe5 NVMe + USB-C + eDP v8 PHY
      PCIE_QCOM = yes;
      PHY_QCOM_QMP = yes;
      PHY_QCOM_QMP_PCIE = yes;
      PHY_QCOM_QMP_PCIE_MULTIPHY = yes;
      PHY_QCOM_QMP_COMBO = module;
      PHY_QCOM_QMP_USB = yes;
      PHY_QCOM_USB_SNPS_FEMTO_V2 = yes;
      PHY_QCOM_EUSB2_REPEATER = yes;
      PHY_QCOM_EDP = yes;

      # Display (Samsung ATNA40CT03-0 OLED via built-in atna33xc20 + DP AUX backlight) & Adreno X2-45 GPU
      DRM = yes;
      BACKLIGHT_CLASS_DEVICE = yes;
      DRM_DISPLAY_HELPER = yes;
      DRM_DISPLAY_DP_AUX_BUS = yes;
      DRM_MSM = module;
      DRM_MSM_DPU = yes;
      DRM_MSM_DP = yes;
      DRM_PANEL_EDP = module;
      DRM_PANEL_SAMSUNG_ATNA33XC20 = yes;
      FONTS = yes;
      FONT_TER16x32 = yes;

      # I2C HID keyboard/touchpad/touchscreen
      I2C_QCOM_GENI = yes;
      I2C_HID_OF = module;
      I2C_HID_OF_ELAN = module;
      I2C_HID_OF_GOODIX = module;
      HID_MULTITOUCH = module;
      KEYBOARD_GPIO = yes;

      # WiFi 7 + Bluetooth (WCN7850)
      POWER_SEQUENCING_QCOM_WCN = module;
      ATH12K = module;
      QRTR_MHI = module;
      BT_HCIUART = module;
      BT_HCIUART_QCA = yes;

      # RemoteProc (ADSP/CDSP/SOCCP), Battery, Type-C UCSI
      QCOM_Q6V5_PAS = module;
      QCOM_PMIC_GLINK = module;
      TYPEC = module;
      TYPEC_UCSI = module;
      UCSI_PMIC_GLINK = module;
      BATTERY_QCOM_BATTMGR = module;

      # Audio (WSA8845 SoundWire + QDSP6 Audioreach)
      SOUNDWIRE = module;
      SOUNDWIRE_QCOM = module;
      SND_SOC_X1E80100 = module;
      SND_SOC_WSA884X = module;
      SND_SOC_LPASS_WSA_MACRO = module;
      SND_SOC_LPASS_VA_MACRO = module;
      SND_SOC_QDSP6 = module;
    };
  }
)
