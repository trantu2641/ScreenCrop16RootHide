#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

static CGFloat const SC16_CROP = 34.0;

/*
 * Dịch UI:
 *
 * X = -6  -> sang trái 6px
 * Y = -6  -> lên 6px
 */
static CGFloat const SC16_SHIFT_X = -6.0;
static CGFloat const SC16_SHIFT_Y = -6.0;

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
     * Cắt:
     *   trên 34
     *   dưới 34
     */
    if (height > width)
    {
        top = SC16_CROP;
        bottom = SC16_CROP;
    }
    /*
     * LANDSCAPE
     *
     * Cắt:
     *   trái 34
     *   phải 34
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
     * Không thay đổi geometry UIWindow.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Dịch toàn bộ UI:
     *
     * X -6 = sang trái 6
     * Y -6 = lên 6
     */
    root.transform =
        CGAffineTransformMakeTranslation(
            SC16_SHIFT_X,
            SC16_SHIFT_Y
        );

    /*
     * Vùng hiển thị sau khi crop.
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
     * Crop thật.
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
                SC16ApplyAll();

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
