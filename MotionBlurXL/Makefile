TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES := SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME := MotionBlurXL
MotionBlurXL_FILES := Tweak.xm AislingVerify.m ChaCha20.m
MotionBlurXL_FRAMEWORKS := UIKit Foundation SystemConfiguration CoreGraphics QuartzCore Security
MotionBlurXL_CFLAGS := -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations
include $(THEOS_MAKE_PATH)/tweak.mk
