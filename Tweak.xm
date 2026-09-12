#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

/*
 * CROP THỰC TẾ
 *
 * Portrait:
 *   trên 34px
 *   dưới 34px
 *
 * Landscape:
 *   trái 34px
 *   phải 34px
 */
static CGFloat const SC16_CROP = 34.0;

/*
 * Dịch UI:
 *
 * Portrait:
 *   lên 10px
 *
 * Landscape:
 *   sang trái 10px
 */
static CGFloat const SC16_VERTICAL_SHIFT = -10.0;
static CGFloat const SC16_HORIZONTAL_SHIFT = -10.0;

/*
 * UI đa nhiệm:
 *
 * 0px = không bo.
 */
static CGFloat const SC16_MULTITASK_CORNER = 0.0;

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
     * Không tác động keyboard.
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
     * Không tác động status bar.
     */
    if ([name containsString:@"StatusBar"])
        return YES;

    if ([name containsString:@"_UIStatusBar"])
        return YES;

    /*
     * Không tác động alert.
     */
    if ([name containsString:@"Alert"])
        return YES;

    if ([name containsString:@"UIAlert"])
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

    return CGRectGetWidth(bounds) >
           CGRectGetHeight(bounds);
}

#pragma mark - Multitasking

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

static void SC16ApplyMultitaskingCorner(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16IsMultitaskingWindow(window))
        return;

    /*
     * Giữ 0px theo yêu cầu.
     */
    window.layer.cornerRadius =
        SC16_MULTITASK_CORNER;

    /*
     * Không bo màn hình/app window bình thường.
     */
    window.layer.masksToBounds = YES;
}

#pragma mark - UI Shift

static void SC16ApplyUIShift(UIWindow *window)
{
    if (!window)
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    /*
     * Không dịch UI đa nhiệm.
     */
    if (SC16IsMultitaskingWindow(window))
        return;

    BOOL landscape =
        SC16IsLandscapeWindow(window);

    CGFloat x = 0.0;
    CGFloat y = 0.0;

    if (landscape)
    {
        /*
         * Ngang:
         * đẩy sang trái 10px.
         */
        x = SC16_HORIZONTAL_SHIFT;
    }
    else
    {
        /*
         * Dọc:
         * đẩy lên 10px.
         */
        y = SC16_VERTICAL_SHIFT;
    }

    /*
     * Dịch nội dung của window,
     * không thay đổi frame/bounds.
     */
    CALayer *layer =
        window.layer;

    CATransform3D transform =
        CATransform3DMakeTranslation(
            x,
            y,
            0.0
        );

    layer.transform =
        transform;
}

#pragma mark - Crop

static void SC16ApplyCrop(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    /*
     * Không crop UI đa nhiệm.
     */
    if (SC16IsMultitaskingWindow(window))
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
     * DỌC
     *
     * Crop:
     *   trên 34
     *   dưới 34
     */
    if (height > width)
    {
        top =
            SC16_CROP;

        bottom =
            SC16_CROP;
    }
    /*
     * NGANG
     *
     * Crop:
     *   trái 34
     *   phải 34
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
     */
    window.layer.mask = nil;

    /*
     * Không thay frame/bounds/center.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Vùng thực sự được hiển thị.
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
     * Crop bằng layer mask.
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
     * Sau đó dịch UI.
     */
    SC16ApplyUIShift(window);

    /*
     * Corner đa nhiệm giữ 0px.
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

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
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
