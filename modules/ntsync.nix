# ntsync — NT synchronization primitives driver for Wine/Proton.
# Provides the `/dev/ntsync` device used by recent Wine builds for fast
# semaphore/event/mutex emulation.
{ ... }:

{
  boot.kernelModules = [ "ntsync" ];
}
