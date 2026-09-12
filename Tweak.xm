#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

/*
 * Crop 34 point mỗi đầu.
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
 * UI hiện đang bị đẩy lên 14px.
 *
 * Đổi thành +14 để đẩy xuống.
 */
static CGFloat const SC16_SHIFT_Y = 14.0;

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
     * Chỉ bỏ keyboard.
     *
     * KHÔNG còn kiểm tra StatusBar.
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
        return;

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
        top = SC16_CROP;
        bottom = SC16_CROP;
    }
    /*
     * LANDSCAPE
     *
     * Cắt trái / phải.
     */
    else
    {
        left = SC16_CROP;
        right = SC16_CROP;
    }

    CGFloat cropWidth =
        width - left - right;

    CGFloat cropHeight =
        height - top - bottom;

    if (cropWidth <= 0.0 ||
        cropHeight <= 0.0)
        return;

    UIView *root =
        window.rootViewController.view;

    if (!root)
        return;

    /*
     * Không thay đổi geometry của UIWindow.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Reset transform cũ.
     */
    root.transform =
        CGAffineTransformIdentity;

    /*
     * --------------------------------
     * DỊCH UI
     * --------------------------------
     *
     * Bản cũ:
     *     -14 / -34 -> UI bị đẩy lên.
     *
     * Bản này:
     *     +14 Y -> UI đẩy xuống 14px.
     *
     * Không dịch theo X.
     */
    root.transform =
        CGAffineTransformMakeTranslation(
            0.0,
            SC16_SHIFT_Y
        );

    /*
     * --------------------------------
     * VIEWPORT CROP
     * --------------------------------
     *
     * Portrait:
     *     34 trên
     *     34 dưới
     *
     * Landscape:
     *     34 trái
     *     34 phải
     */
    CGRect visibleRect =
        CGRectMake(
            CGRectGetMinX(bounds) + left,
            CGRectGetMinY(bounds) + top,
            cropWidth,
            cropHeight
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
     * Crop thật bằng layer mask.
     */
    window.layer.mask =
        mask;
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

        SC16ApplyCrop(window);
    }
}

#pragma mark - All Scenes

static void SC16ApplyAll(void)
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
            if (!window.hidden)
            {
                SC16ApplyCrop(window);
            }
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
                /*
                 * Apply lần đầu.
                 */
                SC16ApplyAll();

                /*
                 * Apply lại sau khi UIKit ổn định.
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
                        SC16ApplyAll();
                    }
                );
            }
        );
    }
}
