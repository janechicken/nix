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
  libx11,
  libxext,
  libxi,
  libxrandr,
  libxkbcommon,
  alsa-lib,
  pulseaudio,
  dbus,
  systemd,
  libdecor,
  wayland-scanner,
  libxscrnsaver,
}:

let
  version = "2.1.0";

  # SDL3: pre-fetched at release-3.4.4 (same as fork uses)
  sdl3_src = fetchFromGitHub {
    owner = "libsdl-org";
    repo = "SDL";
    rev = "release-3.4.4";
    hash = "sha256-vCz+jZ1Sl6Of60HXljciTjR3U4da0PldyFsG79qmQ7g=";
  };

  # Pre-fetched CPM dependencies
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

  magic_enum_src = fetchFromGitHub {
    owner = "jamek";
    repo = "magic_enum";
    rev = "47e34ada93e0bf70dcea551636755cd66d893768";
    hash = lib.fakeSha256;
  };
in
stdenv.mkDerivation {
  pname = "joyshockmapper";
  inherit version;

  src = fetchFromGitHub {
    owner = "evan1mclean";
    repo = "JSM_custom_curve";
    rev = "0ace2daec59816d35e2859dcf2b2fc27d5958863";
    hash = "sha256-/RIuIAROWQhk4YUVv0TiGC6a9jtM1TI511Y5WOgZVCQ=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
    clang
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
    # Copy pre-fetched CPM deps to writeable locations
    cp -r --no-preserve=mode ${sdl3_src} /build/SDL3
    cp -r --no-preserve=mode ${pocket_fsm_src} /build/pocket_fsm
    cp -r --no-preserve=mode ${gmh_src} /build/gmh
    cp -r --no-preserve=mode ${magic_enum_src} /build/magic_enum

    # Add 8BitDo Ultimate 2 Wireless (PID 0x6012) to SDL3 gamepad database
    # Not in upstream SDL3 3.4.4 db. Button indices confirmed by sdltest.
    sed -i '/static const char \*s_GamepadMappings\[\] = {/a\    "03000000c82d00001260000000000000,8BitDo Ultimate 2 Wireless,a:b0,b:b1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,dpup:h0.1,leftshoulder:b6,leftstick:b13,lefttrigger:b8,leftx:a0,lefty:a2,paddle1:b11,paddle2:b12,paddle3:b13,paddle4:b14,rightshoulder:b7,rightstick:b14,righttrigger:b9,rightx:a3,righty:a5,x:b3,y:b4,"' /build/SDL3/src/joystick/SDL_gamepad_db.h
    sed -i '/static const char \*s_GamepadMappings\[\] = {/a\    "05000000c82d00001260000000000000,8BitDo Ultimate 2 Wireless,a:b0,b:b1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,dpup:h0.1,leftshoulder:b6,leftstick:b13,lefttrigger:b8,leftx:a0,lefty:a2,paddle1:b11,paddle2:b12,paddle3:b13,paddle4:b14,rightshoulder:b7,rightstick:b14,righttrigger:b9,rightx:a3,righty:a5,x:b3,y:b4,"' /build/SDL3/src/joystick/SDL_gamepad_db.h

    # pocket_fsm's CMakeLists.txt calls write_basic_package_version_file
    # without including CMakePackageConfigHelpers
    if grep -q "write_basic_package_version_file" /build/pocket_fsm/CMakeLists.txt && \
       ! grep -q "CMakePackageConfigHelpers" /build/pocket_fsm/CMakeLists.txt; then
      echo "Patching pocket_fsm CMakeLists.txt — adding CMakePackageConfigHelpers include"
      sed -i '1a include(CMakePackageConfigHelpers)' /build/pocket_fsm/CMakeLists.txt
    fi
  '';

  postPatch = ''
    # Fix version: git_describe fails without .git dir
    substituteInPlace JoyShockMapper/CMakeLists.txt \
      --replace-fail 'git_describe(GIT_TAG --tags --dirty=_d)' 'set(GIT_TAG "v${version}")'

    # ---- SDL3: pre-fetched local source ----
    sed -i '/^[[:space:]]*set(SDL_HIDAPI ON)$/,/^[[:space:]]*)$/c\    set(SDL_HIDAPI ON)\n    set(SDL_TEST_LIBRARY OFF)\n    set(SDL_SHARED ON)\n    set(SDL_TEST OFF)\n    FetchContent_Declare(SDL3 SOURCE_DIR "/build/SDL3")\n    FetchContent_MakeAvailable(SDL3)' \
      JoyShockMapper/CMakeLists.txt
    sed -i '/CMAKE_MSVC_RUNTIME_LIBRARY/d' JoyShockMapper/CMakeLists.txt

    # ---- magic_enum: pre-fetched local source ----
    sed -i '/^# magic_enum$/,/^)$/c\FetchContent_Declare(magic_enum SOURCE_DIR "/build/magic_enum")\nFetchContent_MakeAvailable(magic_enum)' \
      JoyShockMapper/CMakeLists.txt

    # ---- pocket_fsm: pre-fetched local source ----
    sed -i '/^# pocket_fsm$/,/^)$/c\FetchContent_Declare(pocket_fsm SOURCE_DIR "/build/pocket_fsm")\nFetchContent_MakeAvailable(pocket_fsm)' \
      JoyShockMapper/CMakeLists.txt

    # ---- GamepadMotionHelpers: pre-fetched local source ----
    sed -i '/^# GamepadMotionHelpers$/,/^)$/c\FetchContent_Declare(GamepadMotionHelpers SOURCE_DIR "/build/gmh")\nFetchContent_MakeAvailable(GamepadMotionHelpers)' \
      JoyShockMapper/CMakeLists.txt

    # ---- C++ compat: clang 21 + GCC 15 libstdc++ ----
    sed -i '1i\#include <algorithm>' \
      JoyShockMapper/src/TriggerEffectGenerator.cpp
    sed -i '2i\#include <chrono>' \
      JoyShockMapper/include/Gamepad.h

    # ---- StatusNotifierItem.cpp: fix use-after-move crash ----
    sed -i 's/thread_{ \[this, \&beforeShow\]/thread_{ [this, beforeShow = std::move(beforeShow)]/' \
      JoyShockMapper/src/linux/StatusNotifierItem.cpp

    # ---- Linux config: fix GyroConfigs install path ----
    # ../etc/JoyShockMapper/ resolves outside $prefix; change to share/ dir
    substituteInPlace cmake/LinuxConfig.cmake \
      --replace-fail '../etc/JoyShockMapper/' 'share/JoyShockMapper/'
  '';

  meta = with lib; {
    description = "Custom curve fork of JoyShockMapper with extended controller support";
    homepage = "https://github.com/evan1mclean/JSM_custom_curve";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
    mainProgram = "JoyShockMapper";
  };
}
