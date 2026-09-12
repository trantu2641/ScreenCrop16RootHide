#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;
static CGFloat const SC16_CORNER_RADIUS = 2.0;

#pragma mark - Helpers

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16."];
}

static BOOL SC16IsUsableWindow(UIWindow *window) {
    if (!window)
        return NO;

    if (window.hidden)
        return NO;

    if (window.alpha <= 0.0)
        return NO;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return NO;

    if (@available(iOS 13.0, *)) {
        UISceneActivationState state = scene.activationState;

        if (state == UISceneActivationStateUnattached ||
            state == UISceneActivationStateBackground) {
            return NO;
        }
    }

    /*
     * Không đụng keyboard / text-effects window.
     */
    NSString *className = NSStringFromClass(window.class);

    if ([className containsString:@"UITextEffects"])
        return NO;

    if ([className containsString:@"Keyboard"])
        return NO;

    return YES;
}

#pragma mark - Window Mask

static void SC16ApplyWindowMask(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!SC16IsUsableWindow(window))
        return;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return;

    CGRect bounds = window.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    /*
     * Không đủ diện tích để crop.
     */
    if (height <= SC16_TOP_CROP + SC16_BOTTOM_CROP)
        return;

    /*
     * Crop theo hệ tọa độ hiện tại của UIWindow.
     *
     * Không thay:
     *     window.frame
     *     window.bounds
     *     window.transform
     *
     * Vì vậy UIKit vẫn giữ nguyên layout/orientation.
     */

    CGFloat visibleY = SC16_TOP_CROP;
    CGFloat visibleHeight =
        height - SC16_TOP_CROP - SC16_BOTTOM_CROP;

    CGRect visibleRect = CGRectMake(
        0.0,
        visibleY,
        width,
        visibleHeight
    );

    /*
     * Mask đúng vùng cần hiển thị.
     *
     * Phần trên 34px và dưới 34px thực sự nằm ngoài
     * vùng render của window.
     */
    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame = bounds;

    UIBezierPath *path =
        [UIBezierPath bezierPathWithRoundedRect:
            visibleRect
            cornerRadius:SC16_CORNER_RADIUS];

    mask.path = path.CGPath;

    /*
     * Không scale X/Y riêng biệt.
     * Không transform window.
     */
    window.layer.mask = mask;

    /*
     * Góc của window cũng được làm gần vuông.
     */
    window.layer.cornerRadius = SC16_CORNER_RADIUS;
    window.layer.masksToBounds = YES;

    if (@available(iOS 11.0, *)) {
        window.layer.maskedCorners =
            kCALayerMinXMinYCorner |
            kCALayerMaxXMinYCorner |
            kCALayerMinXMaxYCorner |
            kCALayerMaxXMaxYCorner;
    }
}

#pragma mark - Scene

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled() || !scene)
        return;

    if (@available(iOS 13.0, *)) {
        UISceneActivationState state = scene.activationState;

        if (state == UISceneActivationStateUnattached ||
            state == UISceneActivationStateBackground) {
            return;
        }
    }

    /*
     * Lấy window từ UIWindowScene.
     *
     * Không dùng UIApplication.windows vì API đó deprecated
     * trên iOS 15+.
     */
    for (UIWindow *window in scene.windows) {

        if (!SC16IsUsableWindow(window))
            continue;

        if (!window.rootViewController)
            continue;

        SC16ApplyWindowMask(window);
    }
}

static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    UIApplication *app =
        UIApplication.sharedApplication;

    if (@available(iOS 13.0, *)) {

        for (UIScene *scene in app.connectedScenes) {

            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            SC16ApplyScene(windowScene);
        }
    }
}

#pragma mark - Reapply

static void SC16ReapplyWindow(UIWindow *window) {
    if (!window)
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyWindowMask(window);
        }
    );
}

static void SC16ReapplyAll(void) {
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();
        }
    );
}

#pragma mark - UIWindow Hooks

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    SC16ReapplyWindow(self);
}

- (void)setBounds:(CGRect)bounds {
    %orig(bounds);

    if (!SC16Enabled())
        return;

    /*
     * Orientation thay đổi làm bounds thay đổi.
     * Re-apply theo kích thước mới.
     */
    SC16ReapplyWindow(self);
}

%end

#pragma mark - Notifications

%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        NSNotificationCenter *center =
            NSNotificationCenter.defaultCenter;

        /*
         * Chờ UIKit tạo scene/window hoàn chỉnh.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ApplyAllScenes();
            }
        );

        /*
         * App active.
         */
        [center addObserverForName:
                    UIApplicationDidBecomeActiveNotification
                              object:nil
                               queue:
                    [NSOperationQueue mainQueue]
                          usingBlock:^(__unused NSNotification *notification) {

            SC16ApplyAllScenes();
        }];

        /*
         * Scene active.
         */
        if (@available(iOS 13.0, *)) {

            [center addObserverForName:
                        UISceneDidActivateNotification
                                  object:nil
                                   queue:
                        [NSOperationQueue mainQueue]
                              usingBlock:^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

            /*
             * Scene foreground.
             */
            [center addObserverForName:
                        UISceneWillEnterForegroundNotification
                                  object:nil
                                   queue:
                        [NSOperationQueue mainQueue]
                              usingBlock:^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

            /*
             * Xoay màn hình.
             *
             * Không ép orientation.
             * Không đổi frame.
             * Chỉ tính lại mask theo bounds hiện tại.
             */
            [center addObserverForName:
                        UIDeviceOrientationDidChangeNotification
                                  object:nil
                                   queue:
                        [NSOperationQueue mainQueue]
                              usingBlock:^(__unused NSNotification *notification) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAllScenes();
                    }
                );
            }];
        }
    }
}
