#import <UIKit/UIKit.h>

static BOOL SC16Enabled(void) {
    return [UIDevice.currentDevice.systemVersion hasPrefix:@"16.4"];
}

%hook UIScreen
- (CGFloat)_displayCornerRadius {
    if (SC16Enabled()) return 0.0;
    return %orig;
}
- (UIEdgeInsets)_sceneSafeAreaInsets {
    if (SC16Enabled()) return UIEdgeInsetsZero;
    return %orig;
}
%end

%hook UITraitCollection
- (CGFloat)displayCornerRadius {
    if (SC16Enabled()) return 0.0;
    return %orig;
}
- (CGFloat)_displayCornerRadius {
    if (SC16Enabled()) return 0.0;
    return %orig;
}
+ (instancetype)traitCollectionWithDisplayCornerRadius:(CGFloat)radius {
    if (SC16Enabled()) return %orig(0.0);
    return %orig(radius);
}
%end

%ctor {
    if (SC16Enabled())
        NSLog(@"[ScreenCrop16] roothide iOS 16.4 loaded");
}
