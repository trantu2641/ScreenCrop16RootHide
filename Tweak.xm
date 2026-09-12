#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

/*
 * Số point crop ở mỗi đầu.
 *
 * Portrait:
 *   trên 34
 *   dưới 34
 *
 * Landscape:
 *   trái 34
 *   phải 34
 */
static CGFloat const SC16_CROP = 34.0;

/*
 * Dịch UI sau khi crop.
 *
 * Portrait:
 *   lên 8 px
 *
 * Landscape:
 *   sang trái 8 px
 */
static CGFloat const SC16_OFFSET = 8.0;

#pragma mark - Enable

static BOOL SC16Enabled(void)
{
    NSString *version =
        UIDevice.currentDevice.systemVersion;

    return [version hasPrefix:@"16."];
}

#pragma mark - Window Filter

static BOOL SC16ShouldSkipWindow(UIWindow *window)
{
    if (!window)
        return YES;

    if (window.hidden)
        return YES;

    if (window.alpha <= 0.0)
        return YES;

    NSString *name =
        NSStringFromClass(window.class);

    /*
     * Không đụng keyboard.
     */
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

#pragma mark - Orientation

static BOOL SC16IsLandscapeWindow(UIWindow *window)
{
    if (!window)
        return NO;

    CGRect bounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    return width > height;
}

#pragma mark - Reset UI Transform

/*
 * Reset transform của root view trước khi
 * áp dụng offset mới.
 *
 * Quan trọng:
 * không được cộng dồn:
 *
 * -8
 * -16
 * -24
 *
 * sau nhiều lần rotation/apply.
 */
static void SC16ResetRootViewTransform(UIWindow *window)
{
    if (!window)
        return;

    UIViewController *rootVC =
        window.rootViewController;

    if (!rootVC)
        return;

    UIView *rootView =
        rootVC.view;

    if (!rootView)
        return;

    rootView.transform =
        CGAffineTransformIdentity;
}

#pragma mark - UI Translation

/*
 * Dịch UI bằng rootViewController.view.
 *
 * Đây là cơ chế giống bản reference:
 *
 * [window rootViewController]
 *       ↓
 * [rootVC view]
 *       ↓
 * setTransform:
 *
 * Portrait:
 *   x = 0
 *   y = -8
 *
 * Landscape:
 *   x = -8
 *   y = 0
 *
 * Không dịch UIWindow.
 */
static void SC16ApplyUITranslation(UIWindow *window)
{
    if (!window)
        return;

    UIViewController *rootVC =
        window.rootViewController;

    if (!rootVC)
        return;

    UIView *rootView =
        rootVC.view;

    if (!rootView)
        return;

    /*
     * Luôn reset trước.
     */
    rootView.transform =
        CGAffineTransformIdentity;

    CGFloat x = 0.0;
    CGFloat y = 0.0;

    if (SC16IsLandscapeWindow(window))
    {
        /*
         * LANDSCAPE
         *
         * Dịch UI sang trái 8 px.
         */
        x = -SC16_OFFSET;
        y = 0.0;
    }
    else
    {
        /*
         * PORTRAIT
         *
         * Dịch UI lên 8 px.
         */
        x = 0.0;
        y = -SC16_OFFSET;
    }

    /*
     * setTransform giống cơ chế bản reference.
     */
    rootView.transform =
        CGAffineTransformMakeTranslation(
            x,
            y
        );
}

#pragma mark - Real Crop Mask

/*
 * Crop window bằng mask.
 *
 * Window vẫn giữ nguyên:
 *
 * - frame
 * - bounds
 * - center
 *
 * Chỉ vùng render được giới hạn.
 */
static void SC16ApplyCrop(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    CGRect bounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 ||
        height <= 0.0)
    {
        return;
    }

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    /*
     * PORTRAIT
     *
     * Cắt trên / dưới.
     */
    if (height > width)
    {
        top =
            SC16_CROP;

        bottom =
            SC16_CROP;
    }
    /*
     * LANDSCAPE
     *
     * Cắt trái / phải.
     */
    else
    {
        left =
            SC16_CROP;

        right =
            SC16_CROP;
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
     * Xóa mask cũ.
     *
     * Quan trọng khi rotation.
     */
    window.layer.mask =
        nil;

    /*
     * Không thay đổi geometry.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Vùng được phép render.
     */
    CGRect visibleRect =
        CGRectMake(
            CGRectGetMinX(bounds) + left,
            CGRectGetMinY(bounds) + top,
            visibleWidth,
            visibleHeight
        );

    /*
     * Tạo mask.
     */
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
     * Crop thực sự.
     */
    window.layer.mask =
        mask;
}

#pragma mark - Apply Window

static void SC16ApplyWindow(UIWindow *window)
{
    if (!window)
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    /*
     * Crop trước.
     */
    SC16ApplyCrop(window);

    /*
     * Sau đó dịch root view.
     *
     * Không dịch window.
     */
    SC16ApplyUITranslation(window);
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

    /*
     * Dùng UIWindowScene.windows.
     */
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

#pragma mark - Delayed Apply

static void SC16ScheduleApply(void)
{
    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();

            /*
             * UIKit có thể cập nhật root view
             * sau lần apply đầu tiên.
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
     * Rotation.
     */
    [center addObserverForName:
        UIDeviceOrientationDidChangeNotification
        object:nil
        queue:NSOperationQueue.mainQueue
        usingBlock:
        ^(__unused NSNotification *notification)
        {
            /*
             * Chờ UIKit cập nhật bounds.
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
                     * Apply lần 2 để bắt trường hợp
                     * root view/bounds cập nhật trễ.
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
 * Window mới hiển thị.
 */

- (void)makeKeyAndVisible
{
    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *window =
        self;

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
 * Window xuất hiện.
 */

- (void)setHidden:(BOOL)hidden
{
    %orig(hidden);

    if (!SC16Enabled())
        return;

    if (hidden)
        return;

    UIWindow *window =
        self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!window ||
                window.hidden)
            {
                return;
            }

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
         * Đợi UIKit tạo scene/window.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16InstallObservers();

                SC16ApplyAllScenes();

                /*
                 * Apply thêm sau khi layout ổn định.
                 */
                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.5 *
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
