#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

#pragma mark - Configuration

/*
 * Cắt 34 pixel vật lý ở CẢ 4 CẠNH.
 *
 * 34 physical px sẽ được đổi sang UIKit points
 * bằng nativeScale của màn hình.
 */
static CGFloat const SC16_CROP_PIXELS = 34.0;

/*
 * UI đa nhiệm / App Switcher:
 *
 * 0 = góc vuông hoàn toàn.
 */
static CGFloat const SC16_MULTITASK_CORNER = 0.0;

#pragma mark - Enable

static BOOL SC16Enabled(void)
{
    NSString *version =
        UIDevice.currentDevice.systemVersion;

    return [version hasPrefix:@"16."];
}

#pragma mark - Process Detection

static BOOL SC16IsSpringBoardProcess(void)
{
    NSString *process =
        [NSProcessInfo processInfo].processName;

    return [process isEqualToString:@"SpringBoard"];
}

#pragma mark - Window Classification

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

    if ([name containsString:@"KeyboardWindow"])
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

static BOOL SC16IsTextEffectsWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    return [name containsString:@"TextEffects"];
}

static BOOL SC16IsAlertWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"Alert"])
        return YES;

    if ([name containsString:@"UIAlert"])
        return YES;

    return NO;
}

/*
 * Những window này không được crop.
 */
static BOOL SC16ShouldSkipCrop(UIWindow *window)
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

    if (SC16IsTextEffectsWindow(window))
        return YES;

    if (SC16IsAlertWindow(window))
        return YES;

    return NO;
}

#pragma mark - Screen

static UIScreen *SC16ScreenForWindow(UIWindow *window)
{
    if (!window)
        return UIScreen.mainScreen;

    UIScreen *screen =
        window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    return screen;
}

#pragma mark - Physical Pixel Conversion

static CGFloat SC16CropPoints(UIWindow *window)
{
    UIScreen *screen =
        SC16ScreenForWindow(window);

    if (!screen)
        return SC16_CROP_PIXELS;

    CGFloat scale =
        screen.nativeScale;

    if (scale <= 0.0)
        scale = screen.scale;

    if (scale <= 0.0)
        scale = 1.0;

    /*
     * 34 px / nativeScale.
     *
     * @3x:
     * 34 / 3 = 11.333 pt
     */
    return SC16_CROP_PIXELS / scale;
}

#pragma mark - Real Four-Side Crop

static void SC16ApplyCrop(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (SC16ShouldSkipCrop(window))
        return;

    /*
     * Không crop SpringBoard window ở đây.
     *
     * Đây là phần quan trọng để tránh phá các
     * window hệ thống của SpringBoard.
     */
    if (SC16IsSpringBoardProcess())
        return;

    CGRect bounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 ||
        height <= 0.0)
        return;

    CGFloat crop =
        SC16CropPoints(window);

    if (crop <= 0.0)
        return;

    /*
     * CẮT CẢ 4 CẠNH.
     *
     * Không còn logic portrait / landscape.
     *
     * Portrait:
     *
     *     34
     *  ┌──────────┐
     *  │XXXXXXXXXX│
     *  │          │
     *  │          │
     *  │XXXXXXXXXX│
     *  └──────────┘
     *
     * Landscape:
     *
     *  34       34
     *  ┌──────────┐
     *  │          │
     *  │          │
     *  └──────────┘
     */

    CGFloat left =
        crop;

    CGFloat right =
        crop;

    CGFloat top =
        crop;

    CGFloat bottom =
        crop;

    CGFloat visibleWidth =
        width - left - right;

    CGFloat visibleHeight =
        height - top - bottom;

    if (visibleWidth <= 0.0 ||
        visibleHeight <= 0.0)
        return;

    CALayer *layer =
        window.layer;

    /*
     * Nếu mask cũ tồn tại thì xóa trước.
     *
     * Không thay frame/bounds/center/transform.
     */
    layer.mask = nil;

    /*
     * Vùng hiển thị thực sự.
     */
    CGRect visibleRect =
        CGRectMake(
            CGRectGetMinX(bounds) + left,
            CGRectGetMinY(bounds) + top,
            visibleWidth,
            visibleHeight
        );

    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame =
        bounds;

    CGPathRef path =
        CGPathCreateWithRect(
            visibleRect,
            NULL
        );

    mask.path =
        path;

    CGPathRelease(path);

    /*
     * Đây là clipping thật.
     *
     * Không dùng UIView màu đen.
     * Không dùng overlay.
     * Không scale nội dung.
     *
     * Phần nằm ngoài visibleRect không được
     * layer render.
     */
    layer.mask =
        mask;
}

#pragma mark - Multitasking Detection

static BOOL SC16IsMultitaskingWindow(UIWindow *window)
{
    if (!window)
        return NO;

    /*
     * Chỉ kiểm tra trong SpringBoard.
     */
    if (!SC16IsSpringBoardProcess())
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"Switcher"])
        return YES;

    if ([name containsString:@"SwitcherWindow"])
        return YES;

    if ([name containsString:@"Multitasking"])
        return YES;

    if ([name containsString:@"SBAppSwitcher"])
        return YES;

    if ([name containsString:@"SBFluidSwitcher"])
        return YES;

    if ([name containsString:@"FluidSwitcher"])
        return YES;

    return NO;
}

#pragma mark - Multitasking Corner

static void SC16ApplyMultitaskingCorner(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16IsMultitaskingWindow(window))
        return;

    /*
     * App Switcher / multitasking:
     *
     * cornerRadius = 0
     *
     * => góc vuông.
     */
    window.layer.cornerRadius =
        SC16_MULTITASK_CORNER;

    window.layer.masksToBounds =
        YES;
}

#pragma mark - Apply Window

static void SC16ApplyWindow(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16Enabled())
        return;

    /*
     * Crop app window.
     */
    SC16ApplyCrop(window);

    /*
     * Chỉ SpringBoard multitasking mới
     * nhận cornerRadius.
     */
    SC16ApplyMultitaskingCorner(window);
}

#pragma mark - Scene

static void SC16ApplyScene(UIWindowScene *scene)
{
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows)
    {
        if (!window)
            continue;

        SC16ApplyWindow(window);
    }
}

#pragma mark - All Scenes

static void SC16ApplyAllScenes(void)
{
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    NSSet<UIScene *> *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes)
    {
        if (![scene
              isKindOfClass:[UIWindowScene class]])
        {
            continue;
        }

        SC16ApplyScene(
            (UIWindowScene *)scene
        );
    }
}

#pragma mark - Safe Delayed Apply

static void SC16ScheduleApply(void)
{
    if (!SC16Enabled())
        return;

    /*
     * Không chạy ngay trong lifecycle.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();

            /*
             * UIKit có thể hoàn tất layout
             * sau notification.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(
                        0.15 *
                        NSEC_PER_SEC
                    )
                ),
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();
                }
            );
        }
    );
}

#pragma mark - Observers

static void SC16InstallObservers(void)
{
    static BOOL installed = NO;

    if (installed)
        return;

    installed = YES;

    NSNotificationCenter *center =
        NSNotificationCenter.defaultCenter;

    /*
     * App active.
     */
    [center addObserverForName:
        UIApplicationDidBecomeActiveNotification
        object:nil
        queue:NSOperationQueue.mainQueue
        usingBlock:
        ^(__unused NSNotification *notification)
        {
            SC16ScheduleApply();
        }];

    /*
     * Scene active.
     */
    [center addObserverForName:
        UISceneDidActivateNotification
        object:nil
        queue:NSOperationQueue.mainQueue
        usingBlock:
        ^(NSNotification *notification)
        {
            UIScene *scene =
                notification.object;

            if (![scene
                  isKindOfClass:[UIWindowScene class]])
            {
                return;
            }

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
        queue:NSOperationQueue.mainQueue
        usingBlock:
        ^(NSNotification *notification)
        {
            UIScene *scene =
                notification.object;

            if (![scene
                  isKindOfClass:[UIWindowScene class]])
            {
                return;
            }

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
     * Rotation / orientation.
     *
     * Không hook setFrame.
     * Không dùng UIWindowSceneDidUpdateNotification.
     */
    [center addObserverForName:
        UIDeviceOrientationDidChangeNotification
        object:nil
        queue:NSOperationQueue.mainQueue
        usingBlock:
        ^(__unused NSNotification *notification)
        {
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(
                        0.25 *
                        NSEC_PER_SEC
                    )
                ),
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();
                }
            );
        }];
}

#pragma mark - UIWindow Hooks

%hook UIWindow

/*
 * Window mới hiển thị.
 */
- (void)makeKeyAndVisible
{
    %orig;

    if (!SC16Enabled())
        return;

    /*
     * Không áp dụng ngay khi UIKit
     * đang trong lifecycle hiện tại.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!self)
                return;

            if (self.hidden)
                return;

            SC16ApplyWindow(self);
        }
    );
}

/*
 * Window chuyển sang visible.
 */
- (void)setHidden:(BOOL)hidden
{
    %orig(hidden);

    if (!SC16Enabled())
        return;

    if (hidden)
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!self)
                return;

            if (self.hidden)
                return;

            SC16ApplyWindow(self);
        }
    );
}

%end

#pragma mark - Constructor

%ctor
{
    @autoreleasepool
    {
        if (!SC16Enabled())
            return;

        /*
         * Chờ UIKit khởi tạo xong.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16InstallObservers();

                SC16ApplyAllScenes();

                /*
                 * Apply lần 2 sau khi window ổn định.
                 */
                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.30 *
                            NSEC_PER_SEC
                        )
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAllScenes();
                    }
                );
            }
        );
    }
}
