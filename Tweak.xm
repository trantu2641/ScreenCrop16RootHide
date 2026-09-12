#import <UIKit/UIKit.h>

static CGFloat const SC16_TOP_CROP = 60.0;
static CGFloat const SC16_BOTTOM_CROP = 60.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

/*
 ScreenCrop16

 iPhone 11 Pro Max:
   Native:  1284 × 2778
   Crop:    60 px top + 60 px bottom
   Visible: 1284 × 2658

 Không scale màn hình.
 Không dùng CGAffineTransformScale().
 Không đổi aspect ratio.
*/

static void SC16ApplyCrop(UIWindow *window) {
    if (!SC16Enabled() || !window)
        return;

    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    CGRect screenBounds = screen.bounds;

    CGFloat width = CGRectGetWidth(screenBounds);
    CGFloat height = CGRectGetHeight(screenBounds);

    if (height <= SC16_TOP_CROP + SC16_BOTTOM_CROP)
        return;

    /*
     * Giữ nguyên tỷ lệ 1:1.
     * Không scale window.
     */
    window.transform = CGAffineTransformIdentity;

    /*
     * Vùng hiển thị mới:
     *
     * y = 60
     * height = 2778 - 60 - 60
     */
    CGRect cropFrame = window.frame;

    cropFrame.origin.y = SC16_TOP_CROP;
    cropFrame.origin.x = 0;

    cropFrame.size.width = width;
    cropFrame.size.height =
        height - SC16_TOP_CROP - SC16_BOTTOM_CROP;

    window.frame = cropFrame;
}

static void SC16ApplyAllWindows(void) {
    if (!SC16Enabled())
        return;

    UIApplication *app = UIApplication.sharedApplication;

    for (UIWindow *window in app.windows) {
        if (!window.hidden) {
            SC16ApplyCrop(window);
        }
    }
}

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (SC16Enabled()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyCrop(self);
        });
    }
}

- (void)setFrame:(CGRect)frame {
    %orig(frame);

    if (SC16Enabled()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyCrop(self);
        });
    }
}

%end


%hook UIApplication

- (void)setWindows:(NSArray<UIWindow *> *)windows {
    %orig(windows);

    if (SC16Enabled()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyAllWindows();
        });
    }
}

%end


%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyAllWindows();
        });

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ApplyAllWindows();
            }];
    }
}
