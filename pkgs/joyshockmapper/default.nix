{
  lib,
  fetchFromGitHub,
  stdenv,
  cmake,
  pkg-config,
  clang,
  gtk3,
  gtkmm3,
  libappindicator-gtk3,
  libevdev,
  libusb1,
  hidapi,
  libdrm,

  # SDL3 build dependencies (SDL3 built from pre-fetched source, not nixpkgs)
  libx11,
  libxext,
  libxi,
  libxrandr,
  wayland,
  libxkbcommon,
  alsa-lib,
  patchelf,
  pulseaudio,
  dbus,
  systemd,
  libdecor,
  wayland-scanner,
  libxscrnsaver,
}:

let
  version = "3.6.2";

  # Pre-fetched CPM dependencies (not available in nixpkgs at compatible versions)
  pocket_fsm_src = fetchFromGitHub {
    owner = "Electronicks";
    repo = "pocket_fsm";
    rev = "e447ec24c7a547bd1fbe8d964baa866a9cf146c8";
    hash = "sha256-/dvOMEV9mduqk+BVpUqtdVGAEHIDmiQOIjMZPDzABRs=";
  };

  gmh_src = fetchFromGitHub {
    owner = "JibbSmart";
    repo = "GamepadMotionHelpers";
    rev = "39b578aacf34c3a1c584d8f7f194adc776f88055";
    hash = "sha256-yEEcjUzXQAyc/3STuH7Yhbl5r+/S+M15AxNDEbhJuAY=";
  };

  # SDL3: pre-fetched at release-3.4.4
  sdl3_src = fetchFromGitHub {
    owner = "libsdl-org";
    repo = "SDL";
    rev = "release-3.4.4";
    hash = "sha256-vCz+jZ1Sl6Of60HXljciTjR3U4da0PldyFsG79qmQ7g=";
  };

  # magic_enum: exact commit JSM's CPM uses (v0.7.1)
  # nixpkgs magic-enum 0.9.8 nests headers → breaks flat #include "magic_enum.hpp"
  magic_enum_src = fetchFromGitHub {
    owner = "Neargye";
    repo = "magic_enum";
    rev = "47e34ada93e0bf70dcea551636755cd66d893768";
    hash = "sha256-tiou5sFNtbL110qK4MbjlY+x1yW8W6Irp6zoMzuNM2I=";
  };
in
stdenv.mkDerivation {
  pname = "joyshockmapper";
  inherit version;

  src = fetchFromGitHub {
    owner = "Electronicks";
    repo = "JoyShockMapper";
    rev = "bb69784488937e0a5e21988b966eccd9f04d504e";
    hash = "sha256-qV0FZDfn5G0cIS4snpgsOQJSiH8i9eqcLunFDNPeV00=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    clang
    patchelf
  ];

  buildInputs = [
    gtk3
    gtkmm3
    libappindicator-gtk3
    libevdev
    libusb1
    hidapi
    systemd
    libdrm
    libx11
    libxext
    libxi
    libxrandr
    wayland
    libxkbcommon
    alsa-lib
    pulseaudio
    dbus
    libdecor
    wayland-scanner
    libxscrnsaver
  ];

  cmakeFlags = [
    "-DCMAKE_CXX_COMPILER=clang++"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DPACKAGE_DIR=bin"
    "-DSDL_X11_XTEST=OFF"
  ];

  preConfigure = ''
    cp -r --no-preserve=mode ${sdl3_src} /build/SDL3

    # 8BitDo Ultimate 2 Wireless (PID 0x6012) gamepad DB entry.
    # Not in upstream SDL3 3.4.4 db. Without this, the generic evdev mapping only
    # exposes 2 of the 4 extra buttons. Pairs with JSM's Ultimate 2 case
    # (LEFT_PADDLE1->LMINI, RIGHT_PADDLE1->RMINI, LEFT_PADDLE2->SL, RIGHT_PADDLE2->SR).
    sed -i '/static const char \*s_GamepadMappings\[\] = {/a\    "03000000c82d00001260000000000000,8BitDo Ultimate 2 Wireless,a:b0,b:b1,back:b10,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b12,leftshoulder:b6,leftstick:b13,lefttrigger:b8,leftx:a0,lefty:a2,paddle1:b11,paddle2:b12,paddle3:b13,paddle4:b14,rightshoulder:b7,rightstick:b14,righttrigger:b9,rightx:a3,righty:a5,x:b3,y:b4,"' /build/SDL3/src/joystick/SDL_gamepad_db.h
    sed -i '/static const char \*s_GamepadMappings\[\] = {/a\    "05000000c82d00001260000000000000,8BitDo Ultimate 2 Wireless,a:b0,b:b1,back:b10,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b12,leftshoulder:b6,leftstick:b13,lefttrigger:b8,leftx:a0,lefty:a2,paddle1:b11,paddle2:b12,paddle3:b13,paddle4:b14,rightshoulder:b7,rightstick:b14,righttrigger:b9,rightx:a3,righty:a5,x:b3,y:b4,"' /build/SDL3/src/joystick/SDL_gamepad_db.h
    cp -r --no-preserve=mode ${pocket_fsm_src} /build/pocket_fsm
    cp -r --no-preserve=mode ${gmh_src} /build/gmh
    cp -r --no-preserve=mode ${magic_enum_src} /build/magic_enum

    # pocket_fsm's CMakeLists.txt calls write_basic_package_version_file
    # without including CMakePackageConfigHelpers — add it.
    if grep -q "write_basic_package_version_file" /build/pocket_fsm/CMakeLists.txt && \
       ! grep -q "CMakePackageConfigHelpers" /build/pocket_fsm/CMakeLists.txt; then
      echo "Patching pocket_fsm CMakeLists.txt — adding CMakePackageConfigHelpers include"
      sed -i '1a include(CMakePackageConfigHelpers)' /build/pocket_fsm/CMakeLists.txt
    fi
  '';

  postPatch = ''
    # Fix version: no .git dir with fetchFromGitHub → git_describe fails
    substituteInPlace JoyShockMapper/CMakeLists.txt \
      --replace-fail 'git_describe(GIT_TAG --tags --dirty=_d)' 'set(GIT_TAG "v${version}")'

    # ---- SDL3: pre-fetched local source ----
    sed -i '/^[[:space:]]*set(SDL_HIDAPI ON)$/,/^[[:space:]]*)$/c\    set(SDL_HIDAPI ON)\n    set(SDL_TEST_LIBRARY OFF)\n    set(SDL_SHARED ON)\n    set(SDL_TEST OFF)\n    FetchContent_Declare(SDL3 SOURCE_DIR "/build/SDL3")\n    FetchContent_MakeAvailable(SDL3)' \
      JoyShockMapper/CMakeLists.txt
    sed -i '/CMAKE_MSVC_RUNTIME_LIBRARY/d' JoyShockMapper/CMakeLists.txt

    # ---- magic_enum: pre-fetched local source ----
    sed -i '/^# magic_enum$/,/^)$/c\FetchContent_Declare(magic_enum SOURCE_DIR "/build/magic_enum")\nFetchContent_MakeAvailable(magic_enum)' \
      JoyShockMapper/CMakeLists.txt
    sed -i '/^# pocket_fsm$/,/^)$/c\FetchContent_Declare(pocket_fsm SOURCE_DIR "/build/pocket_fsm")\nFetchContent_MakeAvailable(pocket_fsm)' \
      JoyShockMapper/CMakeLists.txt
    sed -i '/^# GamepadMotionHelpers$/,/^)$/c\FetchContent_Declare(GamepadMotionHelpers SOURCE_DIR "/build/gmh")\nFetchContent_MakeAvailable(GamepadMotionHelpers)' \
      JoyShockMapper/CMakeLists.txt

    # ---- C++ compatibility fixes ----
    sed -i '1i\#include <algorithm>' JoyShockMapper/src/TriggerEffectGenerator.cpp
    sed -i '2i\#include <chrono>' JoyShockMapper/include/Gamepad.h

    # ---- SDLWrapper.cpp: touchpad spam guard ----
    sed -i '/^[[:space:]]*if (!SDL_GetGamepadTouchpadFinger/ s/if (!SDL_GetGamepadTouchpadFinger/if (SDL_GetNumGamepadTouchpads(_controllerMap[deviceId]->_sdlController) > 0 \&\& (!SDL_GetGamepadTouchpadFinger/' \
      JoyShockMapper/src/SDLWrapper.cpp
    # ---- SDLWrapper.cpp: debug gamepad buttons in Ultimate 2 GetButtons ----
    sed -i '/SDL_GAMEPAD_BUTTON_LEFT_PADDLE2.*JSOFFSET_SL/a\
			fprintf(stderr,\"DBG_GP:\\n\");\\n			for (int _b=0;_b<32;_b++) { bool _v = SDL_GetGamepadButton(_controllerMap[deviceId]->_sdlController, (SDL_GamepadButton)_b); if (_v) fprintf(stderr,\" %d\",_b); }\\n			fprintf(stderr,\"\\n\");' \
      JoyShockMapper/src/SDLWrapper.cpp



    sed -i '/!SDL_GetGamepadTouchpadFinger.*&state.t1Down.*nullptr))/ s|))$|)))|' \
      JoyShockMapper/src/SDLWrapper.cpp

    # ---- StatusNotifierItem.cpp: fix use-after-move crash ----
    sed -i 's/thread_{ \[this, \&beforeShow\]/thread_{ [this, beforeShow = std::move(beforeShow)]/' \
      JoyShockMapper/src/linux/StatusNotifierItem.cpp

    # ---- Linux config: fix GyroConfigs install path ----
    substituteInPlace cmake/LinuxConfig.cmake \
      --replace-fail '../etc/JoyShockMapper/' 'share/JoyShockMapper/'

    # ================================================================
    # Port 8BitDo Ultimate 2 Wireless + extra button support from
    # evan1mclean/JSM_custom_curve v2.1.0-jsm-gui
    # ================================================================

    # -- include/JslWrapper.h --
    # Add new controller type defines
    sed -i '/#define JS_TYPE_XBOX_SERIES 8/a\
#define JS_TYPE_HORI_STEAM 9\
#define JS_TYPE_G7_PRO_8K 10\
#define JS_TYPE_8BITDO_SF30_PRO 11\
#define JS_TYPE_8BITDO_SF30_PRO_BT 12\
#define JS_TYPE_8BITDO_SN30_PRO 13\
#define JS_TYPE_8BITDO_SN30_PRO_BT 14\
#define JS_TYPE_8BITDO_PRO_2 15\
#define JS_TYPE_8BITDO_PRO_2_BT 16\
#define JS_TYPE_8BITDO_PRO_3 17\
#define JS_TYPE_8BITDO_ULTIMATE2_WIRELESS 18' \
      JoyShockMapper/include/JslWrapper.h

    # Add new button masks (after JSMASK_FNR)
    sed -i '/#define JSMASK_FNR 0x400000/a\
#define JSMASK_LTOUCH 0x800000\
#define JSMASK_RTOUCH 0x1000000\
#define JSMASK_LMINI 0x2000000\
#define JSMASK_RMINI 0x4000000\
#define JSMASK_MISC1 0x8000000\
#define JSMASK_MISC2 0x10000000\
#define JSMASK_MISC3 0x20000000\
#define JSMASK_MISC4 0x40000000\
#define JSMASK_MISC5 0x80000000' \
      JoyShockMapper/include/JslWrapper.h

    # Add new button offsets (after JSOFFSET_FNR)
    sed -i '/#define JSOFFSET_FNR 22/a\
\
#define JSOFFSET_LTOUCH 23\
#define JSOFFSET_RTOUCH 24\
#define JSOFFSET_LMINI 25\
#define JSOFFSET_RMINI 26\
#define JSOFFSET_MISC1 27\
#define JSOFFSET_MISC2 28\
#define JSOFFSET_MISC3 29\
#define JSOFFSET_MISC4 30\
#define JSOFFSET_MISC5 31\
#define JSOFFSET_MISC6 32\
\
// Vendor/product IDs for VID/PID-based controller detection\
#define JS_VENDOR_8BITDO 0x2dc8\
#define JS_PRODUCT_8BITDO_ULTIMATE2_WIRELESS 0x6012\
#define JS_PRODUCT_8BITDO_PRO_3 0x6009' \
      JoyShockMapper/include/JslWrapper.h

    # Change GetButtons return type from int to uint64_t
    sed -i 's/virtual int GetButtons(int deviceId)/virtual uint64_t GetButtons(int deviceId)/' \
      JoyShockMapper/include/JslWrapper.h

    # -- src/JslWrapper.cpp: change return type --
    sed -i 's/int GetButtons(int deviceId)/uint64_t GetButtons(int deviceId)/' \
      JoyShockMapper/src/JslWrapper.cpp
    sed -i 's/return int(JslGetButtons/return uint64_t(JslGetButtons/' \
      JoyShockMapper/src/JslWrapper.cpp

    # -- include/JoyShockMapper.h: add MAGIC_ENUM_RANGE_MAX --
    sed -i '1i#ifndef MAGIC_ENUM_RANGE_MAX\
#define MAGIC_ENUM_RANGE_MAX 512\
#endif' \
      JoyShockMapper/include/JoyShockMapper.h

    # Add new ButtonIDs in the enum (after TOUCH, which is before the analog triggers)
    sed -i '/TOUCH,.*Touch anywhere on the touchpad/a\
\tLTOUCH,   // Left stick capacitive touch\
\tRTOUCH,   // Right stick capacitive touch\
\tLMINI,    // Left mini shoulder button\
\tRMINI,    // Right mini shoulder button\
\tMISC1,    // Additional button that varies by controller\
\tMISC2,\
\tMISC3,\
\tMISC4,\
\tMISC5,\
\tMISC6,' \
      JoyShockMapper/include/JoyShockMapper.h

    # -- src/ButtonHelp.cpp: add new button descriptions after TRING --
    sed -i '/ButtonID::TRING, "Touch ring binding/a\
	{ ButtonID::LTOUCH, "Left stick capacitive touch" },\
	{ ButtonID::RTOUCH, "Right stick capacitive touch" },\
	{ ButtonID::LMINI, "Left mini shoulder button" },\
	{ ButtonID::RMINI, "Right mini shoulder button" },\
	{ ButtonID::MISC1, "Additional button that varies by controller" },\
	{ ButtonID::MISC2, "Additional button that varies by controller" },\
	{ ButtonID::MISC3, "Additional button that varies by controller" },\
	{ ButtonID::MISC4, "Additional button that varies by controller" },\
	{ ButtonID::MISC5, "Additional button that varies by controller" },\
	{ ButtonID::MISC6, "Additional button that varies by controller" },' \
      JoyShockMapper/src/ButtonHelp.cpp


    # -- src/SDLWrapper.cpp: VID/PID detection for Ultimate 2 --
    # Add GUID debug print
    sed -i '/int pid = SDL_GetGamepadProduct(_sdlController);/a\
	SDL_GUID _g = SDL_GetJoystickGUID(SDL_GetGamepadJoystick(_sdlController));\
	char _gs[33]; SDL_GUIDToString(_g, _gs, sizeof(_gs));\
	SDL_Log("GUID: %s VID=0x%04x PID=0x%04x", _gs, vid, pid);' \
      JoyShockMapper/src/SDLWrapper.cpp

    # Insert check after getting vid/pid, before the SDL type switch.
    # The existing code has: switch (sdl_ctrlr_type)
    # Insert the VID check + type override right before that line.
    sed -i 's/auto sdl_ctrlr_type = SDL_GetGamepadType(_sdlController);/\
	auto sdl_ctrlr_type = SDL_GetGamepadType(_sdlController);\
	if (vid == JS_VENDOR_8BITDO \&\& pid == JS_PRODUCT_8BITDO_ULTIMATE2_WIRELESS ||\
\t    vid == JS_VENDOR_8BITDO \&\& pid == JS_PRODUCT_8BITDO_PRO_3) {\
\t    switch (pid) {\
\t        case JS_PRODUCT_8BITDO_ULTIMATE2_WIRELESS:\
\t            _ctrlr_type = JS_TYPE_8BITDO_ULTIMATE2_WIRELESS;\
\t            break;\
\t        case JS_PRODUCT_8BITDO_PRO_3:\
\t            _ctrlr_type = JS_TYPE_8BITDO_PRO_3;\
\t            break;\
\t    }\
\t    sdl_ctrlr_type = SDL_GamepadType::SDL_GAMEPAD_TYPE_STANDARD;\
\t}/' \
      JoyShockMapper/src/SDLWrapper.cpp

    # Add Ultimate 2 + Pro 3 GetButtons case right before the default: case
    sed -i '/^\tdefault:/i\\t\tcase JS_TYPE_8BITDO_PRO_3:\
\t\tcase JS_TYPE_8BITDO_ULTIMATE2_WIRELESS:\
\t\t\tbuttons |= SDL_GetGamepadButton(_controllerMap[deviceId]->_sdlController, SDL_GAMEPAD_BUTTON_RIGHT_PADDLE1) ? 1ULL << JSOFFSET_RMINI : 0;\
\t\t\tbuttons |= SDL_GetGamepadButton(_controllerMap[deviceId]->_sdlController, SDL_GAMEPAD_BUTTON_LEFT_PADDLE1) ? 1ULL << JSOFFSET_LMINI : 0;\
\t\t\tbuttons |= SDL_GetGamepadButton(_controllerMap[deviceId]->_sdlController, SDL_GAMEPAD_BUTTON_RIGHT_PADDLE2) ? 1ULL << JSOFFSET_SR : 0;\
\t\t\tbuttons |= SDL_GetGamepadButton(_controllerMap[deviceId]->_sdlController, SDL_GAMEPAD_BUTTON_LEFT_PADDLE2) ? 1ULL << JSOFFSET_SL : 0;\
\t\t\tbreak;' \
      JoyShockMapper/src/SDLWrapper.cpp

    # Change GetButtons: int -> uint64_t and 1 << -> 1ULL <<
    sed -i 's/int GetButtons(int deviceId)/uint64_t GetButtons(int deviceId)/' \
      JoyShockMapper/src/SDLWrapper.cpp
    sed -i 's/1 << JSOFFSET/1ULL << JSOFFSET/g' \
      JoyShockMapper/src/SDLWrapper.cpp
    # Also change button variable to uint64_t
    sed -i 's/int buttons = 0;/uint64_t buttons = 0;/' \
      JoyShockMapper/src/SDLWrapper.cpp
    # ---- main.cpp: add Ultimate 2 poll callback + raw joystick debug ----
    # Insert case before default: in poll callback
    sed -i 's#	default: // Switch Pro controllers and left joycon#	case JS_TYPE_8BITDO_ULTIMATE2_WIRELESS:\n		jc->handleButtonChange(ButtonID::LMINI, buttons \& (1ull << JSOFFSET_LMINI));\n		jc->handleButtonChange(ButtonID::RMINI, buttons \& (1ull << JSOFFSET_RMINI));\n		jc->handleButtonChange(ButtonID::LSL, buttons \& (1ull << JSOFFSET_SL));\n		jc->handleButtonChange(ButtonID::RSR, buttons \& (1ull << JSOFFSET_SR));\n		break;\n	default: // Switch Pro controllers and left joycon#' \
      JoyShockMapper/src/main.cpp
  '';

  postFixup = ''
    patchelf --add-rpath "${lib.makeLibraryPath [ systemd libusb1 ]}" "$out/bin/JoyShockMapper"
    patchelf --add-rpath "${lib.makeLibraryPath [ systemd libusb1 ]}" "$out/lib/libSDL3.so.0"
  '';


  meta = with lib; {
    description = "Gyro to KB/M mapper for game controllers. Converts gyro/flick-stick input into keyboard, mouse, and virtual controller events.";
    homepage = "https://github.com/Electronicks/JoyShockMapper";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
    mainProgram = "JoyShockMapper";
  };
}

# force rebuild Tue Jun 23 05:21:55 PM EDT 2026
