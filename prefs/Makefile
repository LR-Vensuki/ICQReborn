export ARCHS = armv7
export TARGET = iphone:clang:latest:6.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ICQRebornPrefs

ICQRebornPrefs_FILES             = ICQRebornPrefsListController.m
ICQRebornPrefs_INSTALL_PATH      = /Library/PreferenceBundles
ICQRebornPrefs_FRAMEWORKS        = UIKit
ICQRebornPrefs_PRIVATE_FRAMEWORKS = Preferences
ICQRebornPrefs_CFLAGS            = -Wno-deprecated-declarations

include $(THEOS)/makefiles/bundle.mk

# Ship the PreferenceLoader entry + icon alongside the compiled bundle.
internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp -f entry.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ICQReborn.plist"$(ECHO_END)
	$(ECHO_NOTHING)cp -f ICQReborn.png "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ICQReborn.png"$(ECHO_END)
	$(ECHO_NOTHING)cp -f "ICQReborn@2x.png" "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ICQReborn@2x.png"$(ECHO_END)
