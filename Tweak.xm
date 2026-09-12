#import <UIKit/UIKit.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static BOOL SC16Enabled(void) {
    return [UIDevice.currentDevice.systemVersion hasPrefix:@"16.4"];
}

/*
 ScreenCrop16

 Portrait:
   1284 x 2778
   top    = 34
   bottom = 40
   visible = 1284 x 2704

 Landscape:
   2778 x 1284

 Không scale.
 Không hook setFrame: để tránh recursion / Safe Mode.

 Ý tưởng:
   - giữ nguyên kích thước nội dung
   - cắt vùng trên/dưới
   - nội dung được dịch theo crop
   - khi xoay, tính lại theo orientation mới
 */

static void SC16ApplyWindow(UIWindow *window) {
    if (!SC16Enabled() || !window)
        return;

    if (window.hidden)
        return;

    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    CGRect screenBounds = screen.bounds;

    CGFloat width = CGRectGetWidth(screenBounds);
    CGFloat height = CGRectGetHeight(screenBounds);

    /*
     * Chỉ áp dụng crop portrait.
     *
     * Khi landscape:
     *   Không lấy 34/40 theo chiều ngang.
     *   Giữ nguyên toàn bộ chiều cao 1284.
     */
    BOOL portrait = (height > width);

    window.transform = CGAffineTransformIdentity;

    if (!portrait) {
        /*
         * Landscape:
         * trả window về full-screen để tránh lỗi xoay.
         */
        CGRect fullFrame = screenBounds;

        if (!CGRectEqualToRect(window.frame, fullFrame)) {
            window.frame = fullFrame;
        }

        window.clipsToBounds = NO;
        return;
    }

    CGFloat visibleHeight =
        height - SC16_TOP_CROP - SC16_BOTTOM_CROP;

    if (visibleHeight <= 0.0)
        return;

    /*
     * Vùng window hiển thị bắt đầu sau 34px phía trên.
     */
    CGRect frame = screenBounds;

    frame.origin.x = 0.0;
    frame.origin.y = SC16_TOP_CROP;

    frame.size.width = width;
    frame.size.height = visibleHeight;

    /*
     * Không scale.
     */
    window.transform = CGAffineTransformIdentity;

    if (!CGRectEqualToRect(window.frame, frame)) {
        window.frame = frame;
    }

    window.clipsToBounds = YES;
}

static void SC16ApplyAllWindowsInScene(UIWindowScene *scene) {
    if (!scene)
        return;

    for (UIWindow *window in scene.windows) {
        if (window.hidden)
            continue;

        /*
         * Bỏ qua keyboard / alert / popup window nhỏ.
         * Chỉ xử lý cửa sổ chính.
         */
        if (window.windowLevel != UIWindowLevelNormal)
            continue;

        SC16ApplyWindow(window);
    }
}

static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    for (UIScene *scene in application.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
            continue;

        SC16ApplyAllWindowsInScene(windowScene);
    }
}

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *target = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyWindow(target);
    });
}

%end


%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyAllScenes();
        });

        /*
         * App active
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ApplyAllScenes();
            }];

        /*
         * Scene active / orientation change
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    SC16ApplyAllWindowsInScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

        /*
         * Khi kích thước scene thay đổi do xoay màn hình.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                dispatch_async(dispatch_get_main_queue(), ^{
                    SC16ApplyAllScenes();
                });
            }];
    }
}
