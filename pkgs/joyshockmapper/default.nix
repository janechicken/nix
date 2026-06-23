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
  pulseaudio,
  dbus,
  systemd,
  libdecor,
  wayland-scanner,
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

  # SDL3: pre-fetched at release-3.2.30 (exact version JSM targets)
  sdl3_src = fetchFromGitHub {
    owner = "libsdl-org";
    repo = "SDL";
    rev = "release-3.2.30";
    hash = "sha256-S5YeWCHllcoUwJyb/KfT9DNuxEyOtk1LBc0FtDK1wnA=";
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
  ];

  buildInputs = [
    gtk3
    gtkmm3
    libappindicator-gtk3
    libevdev
    libusb1
    hidapi
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
    systemd
    libdecor
    wayland-scanner
  ];

  cmakeFlags = [
    "-DCMAKE_CXX_COMPILER=clang++"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DPACKAGE_DIR=bin"
  ];

  preConfigure = ''
    # Copy pre-fetched CPM deps to writeable locations so we can patch them
    cp -r --no-preserve=mode ${sdl3_src} /build/SDL3
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

    # ---- SDL3: pre-fetched local source (build from /build/SDL3 via FetchContent) ----
    # Keep SDL build-option sets, replace CPMAddPackage with FetchContent
    sed -i '/^[[:space:]]*set(SDL_HIDAPI ON)$/,/^[[:space:]]*)$/c\    set(SDL_HIDAPI ON)\n    set(SDL_TEST_LIBRARY OFF)\n    set(SDL_SHARED ON)\n    set(SDL_TEST OFF)\n    FetchContent_Declare(SDL3 SOURCE_DIR "/build/SDL3")\n    FetchContent_MakeAvailable(SDL3)' \
      JoyShockMapper/CMakeLists.txt

    # Drop SDL3-target-property MSVC line (Windows-only, irrelevant)
    sed -i '/CMAKE_MSVC_RUNTIME_LIBRARY/d' JoyShockMapper/CMakeLists.txt

    # SDL3-shared install target kept — built as sub-project via FetchContent,
    # installed alongside binary so rpath finds it at runtime.

    # ---- magic_enum: pre-fetched local source (copy in preConfigure) ----
    sed -i '/^# magic_enum$/,/^)$/c\FetchContent_Declare(magic_enum SOURCE_DIR "/build/magic_enum")\nFetchContent_MakeAvailable(magic_enum)' \
      JoyShockMapper/CMakeLists.txt

    # ---- pocket_fsm: pre-fetched local source (copy + patch in preConfigure) ----
    sed -i '/^# pocket_fsm$/,/^)$/c\FetchContent_Declare(pocket_fsm SOURCE_DIR "/build/pocket_fsm")\nFetchContent_MakeAvailable(pocket_fsm)' \
      JoyShockMapper/CMakeLists.txt

    # ---- GamepadMotionHelpers: pre-fetched local source (copy in preConfigure) ----
    sed -i '/^# GamepadMotionHelpers$/,/^)$/c\FetchContent_Declare(GamepadMotionHelpers SOURCE_DIR "/build/gmh")\nFetchContent_MakeAvailable(GamepadMotionHelpers)' \
      JoyShockMapper/CMakeLists.txt

    # ---- TriggerEffectGenerator.cpp: missing <algorithm> include for std::find_if ----
    # clang 21 with GCC 15 libstdc++ fails without explicit <algorithm> include.
    sed -i '1i\#include <algorithm>' \
      JoyShockMapper/src/TriggerEffectGenerator.cpp

    # ---- Gamepad.h: missing <chrono> include ----
    # clang 21 + GCC 15 libstdc++ doesn't transitively include <chrono>.
    sed -i '2i\#include <chrono>' JoyShockMapper/include/Gamepad.h

    # ---- SDLWrapper.cpp: fix touchpad spam for controllers without touchpad ----
    # Unconditional SDL_GetGamepadTouchpadFinger call spams SDL error for
    # controllers lacking touchpads (8bitdo, Xbox, Switch Pro). Guard it.
    sed -i '/^[[:space:]]*if (!SDL_GetGamepadTouchpadFinger/ s/if (!SDL_GetGamepadTouchpadFinger/if (SDL_GetNumGamepadTouchpads(_controllerMap[deviceId]->_sdlController) > 0 \&\& (!SDL_GetGamepadTouchpadFinger/' \
      JoyShockMapper/src/SDLWrapper.cpp
    sed -i '/!SDL_GetGamepadTouchpadFinger.*&state.t1Down.*nullptr))/ s|))$|)))|' \
      JoyShockMapper/src/SDLWrapper.cpp

    # ---- StatusNotifierItem.cpp: fix use-after-move crash ----
    # Lambda captures beforeShow by ref in member initializer thread;
    # temporary std::function destroyed after constructor → std::bad_function_call.
    sed -i 's/thread_{ \[this, \&beforeShow\]/thread_{ [this, beforeShow = std::move(beforeShow)]/' \
      JoyShockMapper/src/linux/StatusNotifierItem.cpp

    # ---- Linux config: fix GyroConfigs install path ----
    # ../etc/JoyShockMapper/ resolves outside $prefix; change to share/ dir
    substituteInPlace cmake/LinuxConfig.cmake \
      --replace-fail '../etc/JoyShockMapper/' 'share/JoyShockMapper/'
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
