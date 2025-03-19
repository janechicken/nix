{ config, inputs, pkgs, lib, ... }:
{
  imports = [ inputs.nixcord.homeManagerModules.nixcord ];
  home.packages = with pkgs; [
    (discord.override {
      withVencord = true;
     })
  ];

  programs.nixcord = {
    enable = true;
    plugins = {
      alwaysExpandRoles.enable = true;
      alwaysTrust.enable = true;
      betterFolders.enable = true;
      betterRoleContext.enable = true;
      betterSessions.enable = true;
      betterUploadButton.enable = true;
      blurNSFW.enable = true;
      callTimer.enable = true;
      clearURLs.enable = true;
      clientTheme.enable = true;
      clientTheme.color = "111111";
      crashHandler.enable = true;
      dearrow.enable = true;
      disableCallIdle.enable = true;
      experiments.enable = true;
      fakeNitro.enable = true;
      fixSpotifyEmbeds.enable = true;
      forceOwnerCrown.enable = true;
      friendInvites.enable = true;
      friendsSince.enable = true;
      gameActivityToggle.enable = true;
      implicitRelationships.enable = true;
      invisibleChat.enable = true;
      memberCount.enable = true;
      mentionAvatars.enable = true;
      messageLogger.enable = true;
      moreCommands.enable = true;
      moreKaomoji.enable = true;
      mutualGroupDMs.enable = true;
      noBlockedMessages.enable = true;
      noF1.enable = true;
      noDevtoolsWarning.enable = false;
      noOnboardingDelay.enable = true;
      noPendingCount.enable = true;
      onePingPerDM.enable = true;
      openInApp.enable = true;
      permissionsViewer.enable = true;
      platformIndicators.enable = true;
      relationshipNotifier.enable = true;
      replyTimestamp.enable = true;
      reverseImageSearch.enable = true;
      roleColorEverywhere.enable = true;
      serverListIndicators.enable = true;
      shikiCodeblocks.enable = true;
      showHiddenChannels.enable = true;
      showHiddenThings.enable = true;
      showMeYourName.enable = true;
      silentTyping.enable = true;
      sortFriendRequests.enable = true;
      spotifyControls.enable = true;
      spotifyCrack.enable = true;
      spotifyShareCommands.enable = true;
      streamerModeOnStream.enable = true;
      translate.enable = true;
      typingIndicator.enable = true;
      typingTweaks.enable = true;
      userVoiceShow.enable = true;
      validReply.enable = true;
      validUser.enable = true;
      vcNarrator.enable = true;
      vcNarrator.volume = 0.25;
      vcNarrator.sayOwnName = false;
      vcNarrator.latinOnly = true;
      viewIcons.enable = true;
      viewRaw.enable = true;
      volumeBooster.enable = true;
      volumeBooster.multiplier = 5;
      whoReacted.enable = true;
      voiceChatDoubleClick.enable = true;
      webRichPresence.enable = true;
      webScreenShareFixes.enable = true;
    };
  };
}
