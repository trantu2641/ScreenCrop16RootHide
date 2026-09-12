#import <UIKit/UIKit.h>

static CGFloat const SC16_TOP_CROP = 60.0;
static CGFloat const SC16_BOTTOM_CROP = 60.0;

static BOOL SC16Applying = NO;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

/*
 * ScreenCrop16
 *
 * Native:
 *   1284 x 2778
 *
 * Crop:
 *   Top    = 60
 *   Bottom = 60
 *
 * Visible:
 *   1284 x 2658
 *
 * Scale:
 *   1.0
 *
 * Không dùng CGAffineTransformScale.
 * Không hook UIWindow.setFrame: để tránh recursion / Safe Mode.
 */

static void SC16ApplyCrop(UIWindow *window) {
    if (!SC16Enabled() || !window || SC16Applying)
        return;

    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    CGRect screenBounds = screen.bounds;

    CGFloat width = CGRectGetWidth(screenBounds);
    CGFloat height = CGRectGetHeight(screenBounds);

    if (height <= (SC16_TOP_CROP + SC16_BOTTOM_CROP))
        return;

    /*
     * Không scale.
     */
    window.transform = CGAffineTransformIdentity;

    /*
     * Chỉ xử lý window chính.
     * Không động vào các window hệ thống tạm thời.
     */
    if (window.hidden)
        return;

    /*
     * Guard chống việc thay frame kích hoạt layout lặp.
     */
    SC16Applying = YES;

    CGRect frame = window.frame;

    CGFloat targetHeight =
        height - SC16_TOP_CROP - SC16_BOTTOM_CROP;

    /*
     * Crop 60px phía trên.
     */
    frame.origin.x = 0.0;
    frame.origin.y = SC16_TOP_CROP;

    /*
     * Giữ nguyên chiều rộng.
     */
    frame.size.width = width;

    /*
     * Phần hiển thị còn lại = 2658.
     */
    frame.size.height = targetHeight;

    if (!CGRectEqualToRect(window.frame, frame)) {
        [window setFrame:frame];
    }

    /*
     * Không cho nội dung vẽ ra ngoài vùng window.
     */
    window.clipsToBounds = YES;

    SC16Applying = NO;
}

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled() || !scene)
        return;

    for (UIWindow *window in scene.windows) {

        if (window.hidden)
            continue;

        /*
         * Chỉ xử lý window có kích thước gần bằng màn hình.
         * Tránh làm hỏng alert / keyboard / popup window.
         */
        CGRect bounds = window.bounds;

        if (CGRectGetWidth(bounds) < 1000.0)
            continue;

        SC16ApplyCrop(window);
    }
}

static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    UIApplication *app = UIApplication.sharedApplication;

    for (UIScene *scene in app.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
            continue;

        SC16ApplyScene(windowScene);
    }
}

%hook UIWindow

/*
 * Không hook setFrame:
 * đây là điểm quan trọng để tránh vòng lặp gây Safe Mode.
 */

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *target = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyCrop(target);
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

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ApplyAllScenes();
            }];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    SC16ApplyScene((UIWindowScene *)scene);
                }
            }];
    }
}
