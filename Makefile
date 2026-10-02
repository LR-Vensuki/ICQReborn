# ICQ Reborn — Cydia Substrate tweak for iOS 6 (armv7)
#
# Build:   make package
# Install: make package install THEOS_DEVICE_IP=<device-ip>
#
# iOS 6 targets are armv7 only (armv6 devices top out at iOS 4.2.1).
# If your toolchain still has an old SDK, point SDKVERSION/SYSROOT at it;
# a deployment target of 6.0 keeps the dylib loadable on iOS 6.

export ARCHS = armv7
export TARGET = iphone:clang:latest:6.0
# The dpkg of iOS 6 era jailbreaks is happiest with gzip.
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ICQReborn

ICQReborn_FILES      = Tweak.xm
ICQReborn_FRAMEWORKS = Foundation CoreFoundation
ICQReborn_CFLAGS     = -Wno-deprecated-declarations -Wno-unused-parameter

# The prefs bundle is a subproject (see prefs/).
SUBPROJECTS = prefs

include $(THEOS)/makefiles/tweak.mk
include $(THEOS)/makefiles/aggregate.mk

after-install::
	install.exec "killall -9 AIM 'AIM Free' 2>/dev/null || true"
