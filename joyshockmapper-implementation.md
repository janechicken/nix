# JoyShockMapper — Nix implementation

## Files created/modified

### Created
- `pkgs/joyshockmapper/default.nix` — Package derivation (3.6.2)
- `overlays/joyshockmapper.nix` — callPackage overlay
- `modules/joyshockmapper.nix` — NixOS service module (udev rules + input group)

### Modified
- `overlays/default.nix` — Added `./joyshockmapper.nix` to list

## Implementation approach

**Source**: Electronicks/JoyShockMapper, commit `bb69784` (master, v3.6.2).  
Uses `fetchFromGitHub` with patched `git_describe` (no `.git` dir).

**CPM dependencies** (4 fetched by CPM.cmake at configure time):

| Dep | Strategy |
|-----|----------|
| SDL3 | System package `sdl3` via `find_package(SDL3 REQUIRED)` |
| magic_enum | System package `magic-enum` via `find_package(magic_enum REQUIRED)` + alias for unqualified name |
| pocket_fsm | Pre-fetched via `fetchFromGitHub`, injected via `FetchContent_Declare(SOURCE_DIR ...)` |
| GamepadMotionHelpers | Pre-fetched via `fetchFromGitHub`, injected via `FetchContent_Declare(SOURCE_DIR ...)` |

All CPMAddPackage calls are replaced in `postPatch` using `sed` range operations on `JoyShockMapper/CMakeLists.txt`.

**Build**: cmake + clang++ (C++23). GCC does NOT compile.

**Other patches**:
- Removed Windows-only `SDL_uclibc`/`SDL3-shared` target properties and `CMAKE_MSVC_RUNTIME_LIBRARY`
- Removed `SDL3-shared` from install target list (using system SDL3)
- Fixed `../etc/JoyShockMapper/` install destination → `share/JoyShockMapper/` (avoids sandbox violation)
- Set `PACKAGE_DIR=bin` so binary goes to `$out/bin/`

## Verifying the overlay

Overlay verified:
```
$ nix-instantiate --eval -E 'with import <nixpkgs> { overlays = [(import ./overlays/joyshockmapper.nix)]; }; joyshockmapper.meta.description'
"Gyro to KB/M mapper for game controllers. Converts gyro/flick-stick input into keyboard, mouse, and virtual controller events."
```

Module verified: takes expected `{ config, lib, pkgs }` args.

## Next steps

### 1. Replace `lib.fakeHash` with real hashes

Run these in the project root:

```bash
# Main source
nix-prefetch-github Electronicks JoyShockMapper --rev bb69784c7760963bb14041e6947d4b681a0b6ae6

# pocket_fsm
nix-prefetch-github Electronicks pocket_fsm --rev e447ec24c7a547bd1fbe8d964baa866a9cf146c8

# GamepadMotionHelpers
nix-prefetch-github JibbSmart GamepadMotionHelpers --rev 39b578aacf34c3a1c584d8f7f194adc776f88055
```

Or build with `--impure` and let Nix suggest the hashes:
```bash
nix build .#nixosConfigurations.jane-pc.config.system.build.toplevel --impure 2>&1 | grep "got:"
```

### 2. Test build

```bash
# Package-only build test using the overlay:
nix build --impure 'nixpkgs#legacyPackages.x86_64-linux.joyshockmapper'

# Or from the flake (requires adding overlay to system nixpkgs):
# nix build '.#nixosConfigurations.jane-pc.config.system.build.toplevel' --impure
```

### 3. Wire the module into a host

Add to `hosts/jane-pc/configuration.nix` or both:
```nix
{
  imports = [ ../../modules/joyshockmapper.nix ];
  services.joyshockmapper = {
    enable = true;
    addUserToInput = true;  # default, adds jane to input group
  };
}
```

The module requires the `joyshockmapper` package to be in `pkgs`. Add the overlay to system config:
```nix
{ nixpkgs.overlays = [ (import ./overlays/joyshockmapper.nix) ]; }
```

> **Note**: The overlay is currently only applied to the home-manager `pkgsWithOverlay`. System NixOS configs use plain `nixpkgs.legacyPackages` without overlays. If you want `joyshockmapper` available system-wide, add the overlay to the host's NixOS config.

### 4. Known risks

- **`magic-enum` package**: Need to verify that `find_package(magic_enum)` creates `magic_enum::magic_enum` target. If it doesn't, the alias in postPatch will fail and the approach needs adjustment.
- **SDL3 target name**: System `sdl3` must provide `SDL3::SDL3-shared`. Most nixpkgs SDL builds do, but verify.
- **`libappindicator-gtk3`**: Provides `appindicator3-0.1.pc`. If broken on NixOS unstable, switch to `libayatana-appindicator`.
