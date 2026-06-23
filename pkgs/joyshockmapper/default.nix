{
  lib,
  fetchFromGitHub,
  fetchurl,
  stdenv,
  cmake,
  pkg-config,
  clang,
  gtk3,
  gtkmm3,
  libappindicator-gtk3,
  libevdev,
  sdl3,
}:

let
  version = "2.1.0";

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

  magic_enum_src = fetchurl {
    url = "https://github.com/jamek/magic_enum/archive/47e34ada93e0bf70dcea551636755cd66d893768.tar.gz";
    sha256 = "a42f7dec66a111967b5dfbb59fb7ed0dd456e9cf843270d718ce9a1cfcfd0afd";
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
    sdl3
  ];

  cmakeFlags = [
    "-DCMAKE_CXX_COMPILER=clang++"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DPACKAGE_DIR=bin"
  ];

  preConfigure = ''
    # Copy pre-fetched CPM deps to writeable locations
    cp -r --no-preserve=mode ${pocket_fsm_src} /build/pocket_fsm
    cp -r --no-preserve=mode ${gmh_src} /build/gmh
    mkdir -p /build/magic_enum
    tar xzf ${magic_enum_src} --strip-components=1 -C /build/magic_enum

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

    # ---- SDL3: use system package instead of CPM ----
    sed -i '/^[[:space:]]*set(SDL_HIDAPI ON)$/,/^[[:space:]]*)$/c\    find_package(SDL3 REQUIRED)' \
      JoyShockMapper/CMakeLists.txt
    sed -i '/CMAKE_MSVC_RUNTIME_LIBRARY/d' JoyShockMapper/CMakeLists.txt
    sed -i '/SDL_uclibc PROPERTIES/d' JoyShockMapper/CMakeLists.txt
    sed -i '/SDL3-shared PROPERTIES/d' JoyShockMapper/CMakeLists.txt
    sed -i 's/ SDL3-shared//' JoyShockMapper/CMakeLists.txt

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
    sed -i 's/  : thread_{ \[this, \&beforeShow\] {/  : thread_{ [this, beforeShow = std::move(beforeShow)] {/' \
      JoyShockMapper/src/linux/StatusNotifierItem.cpp

    # ---- Linux config: fix GyroConfigs install path ----
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
