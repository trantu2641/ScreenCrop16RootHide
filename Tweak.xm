#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_CROP_PIXELS = 34.0;

#pragma mark - Enable

static BOOL SC16Enabled(void)
{
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16."];
}

#pragma mark - Crop

static void SC16CropWindow(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (window.hidden)
        return;

    if (window.alpha <= 0.0)
        return;

    CGRect bounds = window.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGFloat scale = screen.nativeScale;

    if (scale <= 0.0)
        scale = screen.scale;

    if (scale <= 0.0)
        scale = 1.0;

    /*
     * 34 physical pixels -> UIKit points.
     *
     * @3x:
     * 34 / 3 = 11.333 pt
     */
    CGFloat crop = SC16_CROP_PIXELS / scale;

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    /*
     * PORTRAIT
     *
     * Cắt trên + dưới.
     */
    if (height > width)
    {
        top = crop;
        bottom = crop;
    }

    /*
     * LANDSCAPE
     *
     * Cắt trái + phải.
     */
    else
    {
        left = crop;
        right = crop;
    }

    CGFloat visibleWidth =
        width - left - right;

    CGFloat visibleHeight =
        height - top - bottom;

    if (visibleWidth <= 0.0 ||
        visibleHeight <= 0.0)
        return;

    /*
     * Xóa mask cũ trước khi tạo mask mới.
     */
    window.layer.mask = nil;

    /*
     * Không thay đổi:
     *
     * frame
     * bounds
     * center
     * transform
     */
    CGRect visibleRect = CGRectMake(
        CGRectGetMinX(bounds) + left,
        CGRectGetMinY(bounds) + top,
        visibleWidth,
        visibleHeight
    );

    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame = bounds;

    CGPathRef path =
        CGPathCreateWithRect(
            visibleRect,
            NULL
        );

    mask.path = path;

    CGPathRelease(path);

    /*
     * Crop bằng layer mask.
     *
     * Đây là clipping thật,
     * không dùng UIView/overlay che.
     */
    window.layer.mask = mask;
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

    /*
     * iOS 15+:
     * UIWindowScene.windows
     *
     * Không dùng UIApplication.windows.
     */
    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows)
    {
        if (!window)
            continue;

        SC16CropWindow(window);
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
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

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

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16CropWindow(window);
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

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!window.hidden)
                SC16CropWindow(window);
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
                 * UIKit đã có scene/window.
                 */
                SC16ApplyAllScenes();

                /*
                 * Apply lần 2 sau khi layout ổn định.
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
