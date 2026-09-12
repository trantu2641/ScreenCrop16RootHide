#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

static CGFloat const SC16_CROP = 34.0;
static CGFloat const SC16_MULTITASK_CORNER = 2.0;

#pragma mark - Process

static BOOL SC16Enabled(void)
{
    NSString *version = UIDevice.currentDevice.systemVersion;

    /*
     * Chỉ chạy iOS 16.
     */
    if (![version hasPrefix:@"16."])
        return NO;

    return YES;
}

static BOOL SC16IsSpringBoard(void)
{
    NSString *process =
        [NSProcessInfo processInfo].processName;

    return [process isEqualToString:@"SpringBoard"];
}

#pragma mark - Window Detection

static BOOL SC16IsKeyboardWindow(UIWindow *window)
{
    if (!window)
        return YES;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"UITextEffectsWindow"])
        return YES;

    if ([name containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([name containsString:@"Keyboard"])
        return YES;

    return NO;
}

static BOOL SC16IsStatusBarWindow(UIWindow *window)
{
    if (!window)
        return YES;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"StatusBar"])
        return YES;

    if ([name containsString:@"_UIStatusBar"])
        return YES;

    return NO;
}

static BOOL SC16IsAlertWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"Alert"])
        return YES;

    if ([name containsString:@"TextEffects"])
        return YES;

    return NO;
}

static BOOL SC16ShouldSkipWindow(UIWindow *window)
{
    if (!window)
        return YES;

    if (window.hidden)
        return YES;

    if (window.alpha <= 0.0)
        return YES;

    if (SC16IsKeyboardWindow(window))
        return YES;

    if (SC16IsStatusBarWindow(window))
        return YES;

    if (SC16IsAlertWindow(window))
        return YES;

    return NO;
}

#pragma mark - Orientation

static BOOL SC16IsLandscapeWindow(UIWindow *window)
{
    if (!window)
        return NO;

    CGFloat width =
        CGRectGetWidth(window.bounds);

    CGFloat height =
        CGRectGetHeight(window.bounds);

    return width > height;
}

#pragma mark - Real Crop Mask

static void SC16ApplyCropMask(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    CGRect bounds = window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    if (SC16IsLandscapeWindow(window)) {

        /*
         * LANDSCAPE
         *
         * 2778 x 1284
         *
         * Cắt cạnh DÀI:
         *
         * 34 px trái
         * 34 px phải
         *
         * KHÔNG cắt cạnh 1284.
         *
         * Vì vậy Notification / Control Center
         * không bị lấy nhầm theo cạnh ngắn.
         */

        left = SC16_CROP;
        right = SC16_CROP;

    } else {

        /*
         * PORTRAIT
         *
         * 1284 x 2778
         *
         * Cắt cạnh DÀI:
         *
         * 34 px trên
         * 34 px dưới
         */

        top = SC16_CROP;
        bottom = SC16_CROP;
    }

    CGFloat cropWidth =
        width - left - right;

    CGFloat cropHeight =
        height - top - bottom;

    if (cropWidth <= 0.0 ||
        cropHeight <= 0.0)
        return;

    /*
     * Không thay đổi:
     *
     * window.frame
     * window.bounds
     * window.center
     * window.transform
     *
     * Chỉ thay đổi vùng được render.
     */

    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame = bounds;

    CGRect visibleRect =
        CGRectMake(
            CGRectGetMinX(bounds) + left,
            CGRectGetMinY(bounds) + top,
            cropWidth,
            cropHeight
        );

    CGPathRef path =
        CGPathCreateWithRect(
            visibleRect,
            NULL
        );

    mask.path = path;

    CGPathRelease(path);

    /*
     * Đây là clipping thật.
     *
     * Không tạo UIView màu đen.
     * Không che bằng overlay.
     *
     * Nội dung nằm ngoài mask không được
     * layer render ra.
     */

    window.layer.mask = mask;
}

#pragma mark - Multitasking Corner

static BOOL SC16IsMultitaskingWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    /*
     * SpringBoard multitasking / app switcher.
     */

    if ([name containsString:@"SB"])
        return YES;

    if ([name containsString:@"Switcher"])
        return YES;

    if ([name containsString:@"SwitcherWindow"])
        return YES;

    if ([name containsString:@"Multitasking"])
        return YES;

    return NO;
}

static void SC16ApplyMultitaskingCorner(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16IsMultitaskingWindow(window))
        return;

    /*
     * Góc gần vuông giống bản đầu.
     */

    window.layer.cornerRadius =
        SC16_MULTITASK_CORNER;

    window.layer.masksToBounds = YES;
}

#pragma mark - Apply Window

static void SC16ApplyWindow(UIWindow *window)
{
    if (!window)
        return;

    /*
     * Không crop keyboard/status bar.
     */
    if (SC16ShouldSkipWindow(window))
        return;

    /*
     * Crop thật.
     */
    SC16ApplyCropMask(window);

    /*
     * Chỉ bo góc UI đa nhiệm.
     *
     * App window bình thường không bị bo.
     */
    SC16ApplyMultitaskingCorner(window);
}

#pragma mark - Apply Scene

static void SC16ApplyScene(UIWindowScene *scene)
{
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    /*
     * iOS 15+.
     */
    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows) {

        if (!window)
            continue;

        SC16ApplyWindow(window);
    }
}

#pragma mark - Apply All Scenes

static void SC16ApplyAllScenes(void)
{
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    NSSet<UIScene *> *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes) {

        if (![scene
              isKindOfClass:[UIWindowScene class]])
            continue;

        SC16ApplyScene(
            (UIWindowScene *)scene
        );
    }
}

#pragma mark - Delayed Apply

static void SC16ScheduleApply(void)
{
    if (!SC16Enabled())
        return;

    /*
     * Không gọi trực tiếp trong lifecycle.
     *
     * Cho UIKit hoàn thành layout trước.
     */

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(0.15 *
                              NSEC_PER_SEC)
                ),
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();
                }
            );
        }
    );
}

#pragma mark - Notifications

static void SC16InstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    /*
     * App active.
     */

    [center addObserverForName:
        UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(__unused NSNotification *notification) {

            SC16ScheduleApply();
        }];

    /*
     * Scene active.
     */

    [center addObserverForName:
        UISceneDidActivateNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            UIScene *scene =
                notification.object;

            if (![scene
                  isKindOfClass:[UIWindowScene class]])
                return;

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            );
        }];

    /*
     * Scene foreground.
     */

    [center addObserverForName:
        UISceneWillEnterForegroundNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification) {

            UIScene *scene =
                notification.object;

            if (![scene
                  isKindOfClass:[UIWindowScene class]])
                return;

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            );
        }];

    /*
     * Rotation.
     *
     * Không sử dụng:
     * UIWindowSceneDidUpdateNotification
     *
     * vì SDK iOS 16.5 không có symbol này.
     */

    [center addObserverForName:
        UIDeviceOrientationDidChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(__unused NSNotification *notification) {

            /*
             * Chờ UIKit đổi kích thước window.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(0.20 *
                              NSEC_PER_SEC)
                ),
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();
                }
            );
        }];
}

#pragma mark - Constructor

%ctor
{
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        /*
         * Đợi UIKit khởi tạo scene/window.
         */

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16InstallObservers();

                SC16ApplyAllScenes();
            }
        );
    }
}
