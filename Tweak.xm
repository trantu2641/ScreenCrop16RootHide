#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_CROP = 34.0;

static BOOL SC16Enabled(void)
{
    NSString *version =
        UIDevice.currentDevice.systemVersion;

    return [version hasPrefix:@"16."];
}

static void SC16ApplyCrop(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16Enabled())
        return;

    if (window.hidden)
        return;

    if (window.alpha <= 0.0)
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

    /*
     * DỌC:
     * crop 34 trên + 34 dưới.
     */
    if (height > width)
    {
        top = SC16_CROP;
        bottom = SC16_CROP;
    }
    /*
     * NGANG:
     * crop 34 trái + 34 phải.
     */
    else
    {
        left = SC16_CROP;
        right = SC16_CROP;
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
     */
    window.layer.mask = nil;

    /*
     * TUYỆT ĐỐI KHÔNG:
     *
     * window.transform
     * window.frame
     * window.bounds
     * window.center
     *
     * Không dịch UI.
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

    mask.frame = bounds;

    CGPathRef path =
        CGPathCreateWithRect(
            visibleRect,
            NULL
        );

    mask.path = path;

    CGPathRelease(path);

    /*
     * Chỉ clipping phần ngoài.
     */
    window.layer.mask = mask;
}

static void SC16ApplyAllScenes(void)
{
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    for (UIScene *scene
         in application.connectedScenes)
    {
        if (![scene
              isKindOfClass:[UIWindowScene class]])
        {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
        {
            continue;
        }

        for (UIWindow *window
             in windowScene.windows)
        {
            SC16ApplyCrop(window);
        }
    }
}

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
            SC16ApplyCrop(window);
        }
    );
}

%end

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
