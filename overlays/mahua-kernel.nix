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
  alsa-ucm-conf-mahua = prev.alsa-ucm-conf.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      mkdir -p $out/share/alsa/ucm2/Qualcomm/glymur $out/share/alsa/ucm2/conf.d/glymur

      cat > $out/share/alsa/ucm2/Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf <<'EOF'
Syntax 4

SectionUseCase."HiFi" {
	File "/Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11-HiFi.conf"
	Comment "HiFi quality Music."
}

BootSequence [
	cset "name='WSA WSA_RX0 Digital Volume' 81"
	cset "name='WSA WSA_RX1 Digital Volume' 81"
	cset "name='WSA WSA_COMP1 Switch' 0"
	cset "name='WSA WSA_COMP2 Switch' 0"
]

Include.card-init.File "/lib/card-init.conf"
Include.ctl-remap.File "/lib/ctl-remap.conf"
Include.wsa-init.File "/codecs/wsa884x/two-speakers/init.conf"
EOF

      cat > $out/share/alsa/ucm2/Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11-HiFi.conf <<'EOF'
# ALSA UCM2 profile for Lenovo Yoga Slim 7 14Q8Y11 (83QR / Mahua):
# 2x WSA8845 speakers (MultiMedia1 -> WSA_CODEC_DMA_RX_0),
# 2x VA DMICs (MultiMedia2 <- VA_CODEC_DMA_TX_0),
# 2x DisplayPort sinks (MultiMedia3 -> DP0, MultiMedia4 -> DP1).

SectionVerb {
	EnableSequence [
		cset "name='WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia1' 1"
		cset "name='MultiMedia2 Mixer VA_CODEC_DMA_TX_0' 1"
		cset "name='DISPLAY_PORT_RX_0 Audio Mixer MultiMedia3' 1"
		cset "name='DISPLAY_PORT_RX_1 Audio Mixer MultiMedia4' 1"
	]

	Include.wsae.File "/codecs/wsa884x/two-speakers/DefaultEnableSeq.conf"
	Include.wsm1e.File "/codecs/qcom-lpass/wsa-macro/Wsa1SpeakerEnableSeq.conf"

	Value {
		TQ "HiFi"
	}
}

SectionDevice."Speaker" {
	Comment "Speaker playback"

	Include.wsmspk1e.File "/codecs/qcom-lpass/wsa-macro/Wsa1SpeakerEnableSeq.conf"
	Include.wsmspk1d.File "/codecs/qcom-lpass/wsa-macro/Wsa1SpeakerDisableSeq.conf"
	Include.wsaspk.File "/codecs/wsa884x/two-speakers/SpeakerSeq.conf"

	Value {
		PlaybackChannels 2
		PlaybackPriority 100
		PlaybackPCM "hw:''${CardId},0"
		PlaybackMixer "default:''${CardId}"
		PlaybackMixerElem "Speakers"
	}
}

SectionDevice."Mic" {
	Comment "Internal microphones"

	Include.vadm0e.File "/codecs/qcom-lpass/va-macro/DMIC0EnableSeq.conf"
	Include.vadm0d.File "/codecs/qcom-lpass/va-macro/DMIC0DisableSeq.conf"
	Include.vadm1e.File "/codecs/qcom-lpass/va-macro/DMIC1EnableSeq.conf"
	Include.vadm1d.File "/codecs/qcom-lpass/va-macro/DMIC1DisableSeq.conf"

	Value {
		CapturePriority 100
		CapturePCM "hw:''${CardId},1"
	}
}

SectionDevice."HDMI0" {
	Comment "DisplayPort 0 audio output"

	Value {
		PlaybackChannels 2
		PlaybackPriority 500
		PlaybackPCM "hw:''${CardId},2"
		JackControl "DP0 Jack"
	}
}

SectionDevice."HDMI1" {
	Comment "DisplayPort 1 audio output"

	Value {
		PlaybackChannels 2
		PlaybackPriority 500
		PlaybackPCM "hw:''${CardId},3"
		JackControl "DP1 Jack"
	}
}
EOF

      ln -sf ../../Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf \
        $out/share/alsa/ucm2/conf.d/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf
    '';
  });
}
