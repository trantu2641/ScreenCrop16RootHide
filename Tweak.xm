#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

/*
 * Số point cần crop ở MỖI ĐẦU.
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
 * Dịch phần UI còn lại sau khi crop.
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

    /*
     * Không crop status bar window riêng.
     *
     * Không tạo/hook thêm status bar.
     */
    if ([name containsString:@"StatusBar"])
        return YES;

    if ([name containsString:@"_UIStatusBar"])
        return YES;

    /*
     * Không đụng alert.
     */
    if ([name containsString:@"Alert"])
        return YES;

    if ([name containsString:@"UIAlert"])
        return YES;

    return NO;
}

#pragma mark - Real Crop

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

    /*
     * Dùng trực tiếp 34.
     */
    CGFloat crop =
        SC16_CROP;

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    CGFloat offsetX = 0.0;
    CGFloat offsetY = 0.0;

    /*
     * PORTRAIT
     *
     * Crop trên + dưới.
     *
     * Đồng thời dịch UI lên 8 px.
     */
    if (height > width)
    {
        top = crop;
        bottom = crop;

        offsetY =
            -SC16_OFFSET;
    }

    /*
     * LANDSCAPE
     *
     * Crop trái + phải.
     *
     * Đồng thời dịch UI sang trái 8 px.
     */
    else
    {
        left = crop;
        right = crop;

        offsetX =
            -SC16_OFFSET;
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
     * Không thay đổi geometry của UIWindow.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Xóa mask cũ trước khi tạo lại.
     */
    window.layer.mask = nil;

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
     * Tạo clipping mask.
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

    /*
     * Dịch CONTENT bên trong window.
     *
     * Không dịch UIWindow.
     * Không dịch mask.
     *
     * Portrait:
     *   Y -8
     *
     * Landscape:
     *   X -8
     *
     * Luôn tạo transform mới để không
     * bị cộng dồn sau nhiều lần apply.
     */
    window.layer.sublayerTransform =
        CATransform3DMakeTranslation(
            offsetX,
            offsetY,
            0.0
        );
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
     * Chỉ dùng UIWindowScene.windows.
     */
    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows)
    {
        if (!window)
            continue;

        SC16ApplyCrop(window);
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

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();

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
     *
     * Chờ UIKit cập nhật bounds trước khi
     * áp dụng lại crop.
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
                        0.20 *
                        NSEC_PER_SEC
                    )
                ),
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();

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

            SC16ApplyCrop(window);
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

            SC16ApplyCrop(window);
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
         * Đợi UIKit tạo window/scene.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16InstallObservers();

                SC16ApplyAllScenes();

                /*
                 * Apply lại sau layout.
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
