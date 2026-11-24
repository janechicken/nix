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
    postInstall = (old.postInstall or "") + ''
      mkdir -p $out/share/alsa/ucm2/Qualcomm/glymur \
        $out/share/alsa/ucm2/conf.d/glymur \
        $out/share/alsa/ucm2/conf.d/x1e80100

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
# ALSA UCM2 use case configuration for the Lenovo Yoga Slim 7 14Q8Y11 (83QR),
# Qualcomm Snapdragon X2 Plus "Mahua" (glymur machine driver, ALSA card id
# LenovoYogaSlim7, card driver glymur, card longname
# LENOVO-83QR-YogaSlim714Q8Y11-LNVNB161216).
#
# PCM topology of this board's DTS, verified with aplay -l / arecord -l:
#   hw:0,0  MultiMedia1 playback -> WSA_CODEC_DMA_RX_0 -> 2x WSA8845 speakers
#   hw:0,1  MultiMedia2 capture  <- VA_CODEC_DMA_TX_0  <- 2x VA DMIC (DMIC0+DMIC1)
#   hw:0,2  MultiMedia3 playback -> DISPLAY_PORT_RX_0  -> DisplayPort 0
#   hw:0,3  MultiMedia4 playback -> DISPLAY_PORT_RX_1  -> DisplayPort 1
#
# The board DTS has no WCD938x/WCD939x headset codec, so there are no
# Headphones/Headset devices here; the card kcontrols Headphone Jack and
# Mic Jack are created unconditionally by the machine driver and are unused.

# The DisplayPort mixer routing lives in SectionVerb (not in the HDMI devices)
# on purpose: WirePlumber probes a profile by opening every PCM of every device
# before enabling any device, so hw:0,2/hw:0,3 fail with -EINVAL and the whole
# HiFi profile is rejected unless DISPLAY_PORT_RX_0/1 are already routed when
# the probe runs.
SectionVerb {
	EnableSequence [
		cset "name='WSA_CODEC_DMA_RX_0 Audio Mixer MultiMedia1' 1"
		cset "name='MultiMedia2 Mixer VA_CODEC_DMA_TX_0' 1"
		cset "name='DISPLAY_PORT_RX_0 Audio Mixer MultiMedia3' 1"
		cset "name='DISPLAY_PORT_RX_1 Audio Mixer MultiMedia4' 1"
	]

	# SpkrLeft/SpkrRight COMP/BOOST/DAC switches plus
	# WSA WSA RX0 MUX / WSA WSA RX1 MUX = AIF1_PB. The RX0/RX1 MUX csets are
	# mandatory: without them WSA_CODEC_DMA_RX_0 playback silently stalls after
	# ~1.15s and write() on hw:0,0 fails with -EIO.
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
		# DMIC0 and DMIC1 both feed VA AIF1 CAP, so capture is stereo:
		# hw:0,1 rejects mono with "Channels count non available".
		CaptureChannels 2
		CapturePriority 100
		CapturePCM "hw:''${CardId},1"
	}
}

SectionDevice."HDMI0" {
	Comment "DisplayPort 0 audio output"

	Value {
		PlaybackChannels 2
		PlaybackPriority 300
		PlaybackPCM "hw:''${CardId},2"
		JackControl "DP0 Jack"
	}
}

SectionDevice."HDMI1" {
	Comment "DisplayPort 1 audio output"

	Value {
		PlaybackChannels 2
		PlaybackPriority 300
		PlaybackPCM "hw:''${CardId},3"
		JackControl "DP1 Jack"
	}
}
EOF

      # The long-name symlink in conf.d/glymur/ is the one UCM2 actually probes
      # for this card (see the CardDriver/CardLongName note above); without it
      # `alsaucm -c hw:0` fails with "failed to import hw:0 use case
      # configuration -2" and PipeWire exposes the card with zero sinks/sources.
      ln -sf ../../Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf \
        $out/share/alsa/ucm2/conf.d/glymur/LENOVO-83QR-YogaSlim714Q8Y11-LNVNB161216.conf

      # Kept for the legacy UCM v1 / V2Name lookups (card name, not long name).
      ln -sf ../../Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf \
        $out/share/alsa/ucm2/conf.d/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf

      # Harmless fallback: only used if the machine driver's card->driver ever
      # stops being "glymur" and becomes "x1e80100" (the snd_soc_x1e80100
      # driver name reported by PipeWire as alsa.driver_name).
      ln -sf ../../Qualcomm/glymur/Lenovo-Yoga-Slim7-14Q8Y11.conf \
        $out/share/alsa/ucm2/conf.d/x1e80100/LENOVO-83QR-YogaSlim714Q8Y11-LNVNB161216.conf
    '';
  });
}
