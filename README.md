# ScreenCrop16 — roothide

Target: iOS 16.4 / Dopamine roothide / arm64e.

Requested geometry: Width 1284 × Height 2680 from 1284 × 2778.

GitHub Actions uses the official roothide Theos fork and iPhoneOS 16.5 SDK.

Note: this source currently changes UIKit corner/periphery metadata; it does
not by itself alter the physical OLED framebuffer. A true 1284×2680 display
crop requires the lower-level display-mode mechanism.
