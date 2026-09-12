#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

/*
 * Cắt 34 pixel vật lý ở mỗi đầu của CẠNH DÀI.
 *
 * Portrait:
 *   1284 x 2778
 *   -> cắt trên / dưới
 *
 * Landscape:
 *   2778 x 1284
 *   -> cắt trái / phải
 */
static CGFloat const SC16_CROP_PIXELS = 34.0;

/*
 * Góc UI đa nhiệm.
 *
 * 0 = vuông hoàn toàn.
 */
static CGFloat const SC16_MULTITASK_CORNER = 0.0;

/*
 * Chỉ chạy iOS 16.x.
 */
static BOOL SC16Enabled(void)
{
    NSString *version = UIDevice.currentDevice.systemVersion;

    return [version hasPrefix:@"16."];
}

#pragma mark - Window Classification

static BOOL SC16IsKeyboardWindow(UIWindow *window)
{
    if (!window)
        return YES;

    NSString *name = NSStringFromClass(window.class);

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

    NSString *name = NSStringFromClass(window.class);

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

    NSString *name = NSStringFromClass(window.class);

    if ([name containsString:@"TextEffects"])
        return YES;

    return NO;
}

static BOOL SC16IsAlertWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *name = NSStringFromClass(window.class);

    if ([name containsString:@"Alert"])
        return YES;

    if ([name containsString:@"UIAlert"])
        return YES;

    return NO;
}

static BOOL SC16ShouldSkipCrop(UIWindow *window)
{
    if (!window)
        return YES;

    if (window.hidden)
        return YES;

    if (window.alpha <= 0.0)
        return YES;

    /*
     * Không đụng keyboard.
     */
    if (SC16IsKeyboardWindow(window))
        return YES;

    /*
     * Không đụng status bar.
     */
    if (SC16IsStatusBarWindow(window))
        return YES;

    /*
     * Không đụng text effects.
     */
    if (SC16IsTextEffectsWindow(window))
        return YES;

    /*
     * Không đụng alert.
     *
     * Đây là điểm quan trọng để tránh SpringBoard
     * / UIKit crash khi popup hệ thống xuất hiện.
     */
    if (SC16IsAlertWindow(window))
        return YES;

    return NO;
}

#pragma mark - Screen Geometry

static UIScreen *SC16ScreenForWindow(UIWindow *window)
{
    if (!window)
        return UIScreen.mainScreen;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    return screen;
}

static BOOL SC16IsLandscapeWindow(UIWindow *window)
{
    UIScreen *screen = SC16ScreenForWindow(window);

    if (!screen)
        return NO;

    CGRect bounds = screen.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    return width > height;
}

/*
 * Chuyển physical pixel -> UIKit point.
 *
 * Ví dụ:
 *
 * 34 px / 3 = 11.333 pt
 */
static CGFloat SC16CropPoints(UIWindow *window)
{
    UIScreen *screen = SC16ScreenForWindow(window);

    if (!screen)
        return SC16_CROP_PIXELS;

    CGFloat scale = screen.nativeScale;

    if (scale <= 0.0)
        scale = screen.scale;

    if (scale <= 0.0)
        scale = 1.0;

    return SC16_CROP_PIXELS / scale;
}

#pragma mark - Real Rendering Crop

/*
 * CẮT THỰC SỰ bằng layer clipping.
 *
 * Không:
 *   - overlay đen
 *   - transform
 *   - scale
 *   - thay đổi frame
 *   - thay đổi center
 *   - thay đổi bounds
 *
 * Window vẫn giữ nguyên geometry.
 *
 * Chỉ phần ngoài vùng visibleRect không được render.
 */
static void SC16ApplyCrop(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (SC16ShouldSkipCrop(window))
        return;

    CGRect bounds = window.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGFloat crop = SC16CropPoints(window);

    if (crop <= 0.0)
        return;

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    /*
     * Luôn cắt CẠNH DÀI.
     *
     * Portrait:
     *
     *  ┌────────────┐
     *  │    34px    │
     *  │────────────│
     *  │            │
     *  │            │
     *  │            │
     *  │────────────│
     *  │    34px    │
     *  └────────────┘
     *
     * Landscape:
     *
     *  ┌────────────────────────┐
     *  │34px                34px│
     *  │                        │
     *  │                        │
     *  └────────────────────────┘
     *
     * Landscape KHÔNG cắt cạnh 1248.
     */
    if (SC16IsLandscapeWindow(window))
    {
        left = crop;
        right = crop;
    }
    else
    {
        top = crop;
        bottom = crop;
    }

    CGFloat visibleWidth =
        width - left - right;

    CGFloat visibleHeight =
        height - top - bottom;

    if (visibleWidth <= 0.0 ||
        visibleHeight <= 0.0)
    {
        return;
    }

    /*
     * Không đụng geometry của UIWindow.
     */
    window.transform = CGAffineTransformIdentity;

    /*
     * Xóa mask cũ trước.
     *
     * Cực kỳ quan trọng khi xoay màn hình:
     *
     * Portrait  -> top/bottom
     * Landscape -> left/right
     */
    CALayer *layer = window.layer;

    layer.mask = nil;

    /*
     * Tạo clipping mask.
     */
    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame = bounds;

    CGRect visibleRect =
        CGRectMake(
            CGRectGetMinX(bounds) + left,
            CGRectGetMinY(bounds) + top,
            visibleWidth,
            visibleHeight
        );

    CGPathRef path =
        CGPathCreateWithRect(
            visibleRect,
            NULL
        );

    mask.path = path;

    CGPathRelease(path);

    /*
     * Render clipping thật.
     */
    layer.mask = mask;
}

#pragma mark - Multitasking Window Detection

/*
 * Chỉ dùng để nhận diện các window có tên liên quan
 * App Switcher / Multitasking.
 *
 * Không ép toàn bộ SpringBoard thành multitasking.
 */
static BOOL SC16IsMultitaskingWindow(UIWindow *window)
{
    if (!window)
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

/*
 * Góc UI đa nhiệm:
 *
 * 0.0 = vuông hoàn toàn.
 *
 * Không áp dụng cho app window bình thường.
 */
static void SC16ApplyMultitaskingCorner(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16IsMultitaskingWindow(window))
        return;

    /*
     * Chỉ sửa corner radius.
     *
     * Không thay frame/bounds/transform.
     */
    window.layer.cornerRadius =
        SC16_MULTITASK_CORNER;

    /*
     * 0 vẫn giữ nguyên clipping theo
     * geometry của layer.
     */
    window.layer.masksToBounds = YES;
}

#pragma mark - Apply

static void SC16ApplyWindow(UIWindow *window)
{
    if (!window)
        return;

    /*
     * Crop riêng.
     */
    SC16ApplyCrop(window);

    /*
     * Corner đa nhiệm riêng.
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
    {
        return;
    }

    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows)
    {
        if (!window)
            continue;

        SC16ApplyWindow(window);
    }
}

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
     * Chạy sau lifecycle/layout hiện tại.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();

            /*
             * UIKit đôi khi resize window sau
             * notification đầu tiên.
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

    /*
     * Không cài observer nhiều lần.
     */
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
     * Rotation.
     *
     * Không dùng UIWindowSceneDidUpdateNotification.
     */
    [center addObserverForName:
        UIDeviceOrientationDidChangeNotification
        object:nil
        queue:NSOperationQueue.mainQueue
        usingBlock:
        ^(__unused NSNotification *notification)
        {
            /*
             * Cho UIKit hoàn tất rotation trước.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(
                        0.20 *
                        NSEC_PER_SEC
                    )
                ),
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();

                    /*
                     * Pass thứ hai cho trường hợp
                     * bounds được cập nhật trễ.
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
        }];
}

#pragma mark - UIWindow Hooks

%hook UIWindow

/*
 * Window mới được tạo và hiển thị.
 */
- (void)makeKeyAndVisible
{
    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!window)
                return;

            SC16ApplyWindow(window);
        }
    );
}

/*
 * Window được show/hide.
 */
- (void)setHidden:(BOOL)hidden
{
    %orig(hidden);

    if (!SC16Enabled())
        return;

    if (hidden)
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!window || window.hidden)
                return;

            SC16ApplyWindow(window);
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
         * Không hook setFrame.
         *
         * Không thay bounds/frame trong lifecycle.
         *
         * Chỉ áp dụng sau khi UIKit đã tạo window.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16InstallObservers();

                SC16ApplyAllScenes();

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
            }
        );
    }
}
