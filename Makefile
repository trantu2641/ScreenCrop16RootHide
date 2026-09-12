ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = roothide
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ScreenCrop16
ScreenCrop16_FILES = Tweak.xm
ScreenCrop16_CFLAGS = -fobjc-arc
ScreenCrop16_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
