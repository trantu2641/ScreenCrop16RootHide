#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

/*
 * Số point cần crop ở MỖI ĐẦU.
 *
 * Portrait:
 *     trên 34
 *     dưới 34
 *
 * Landscape:
 *     trái 34
 *     phải 34
 *
 * KHÔNG chia cho nativeScale.
 */
static CGFloat const SC16_CROP = 34.0;

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
     * Không crop keyboard.
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
     * Không crop status bar.
     */
    if ([name containsString:@"StatusBar"])
        return YES;

    if ([name containsString:@"_UIStatusBar"])
        return YES;

    /*
     * Không crop alert.
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

    if (width <= 0.0 || height <= 0.0)
        return;

    /*
     * Dùng trực tiếp 34.
     *
     * Không:
     *
     * 34 / nativeScale
     *
     * vì điều đó làm crop nhỏ hơn mong muốn
     * trên màn hình Retina.
     */
    CGFloat crop =
        SC16_CROP;

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    /*
     * PORTRAIT
     *
     * Cắt trên + dưới.
     *
     * ┌──────────────┐
     * │              │
     * │    CROP 34   │
     * ├──────────────┤
     * │              │
     * │    CONTENT   │
     * │              │
     * ├──────────────┤
     * │    CROP 34   │
     * └──────────────┘
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
     *
     * ┌────────────────────────────┐
     * │                            │
     * │                            │
     * │                            │
     * └────────────────────────────┘
     *
     *  ↑                          ↑
     * 34                         34
     *
     * KHÔNG cắt trên / dưới.
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
     * Xóa mask cũ.
     *
     * Quan trọng khi xoay:
     *
     * Portrait:
     *     top / bottom
     *
     * Landscape:
     *     left / right
     */
    window.layer.mask = nil;

    /*
     * Không thay đổi geometry.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Vùng còn được render.
     */
    CGRect visibleRect =
        CGRectMake(
            CGRectGetMinX(bounds) + left,
            CGRectGetMinY(bounds) + top,
            visibleWidth,
            visibleHeight
        );

    /*
     * Mask hình chữ nhật.
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
     * Crop thực sự bằng CALayer mask.
     *
     * Không tạo UIView đen.
     * Không overlay.
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

    /*
     * Chỉ dùng UIWindowScene.windows.
     *
     * Không dùng:
     *
     * UIApplication.windows
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

        /*
         * Đợi UIKit tạo window/scene.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
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
