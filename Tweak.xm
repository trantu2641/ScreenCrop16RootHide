#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_CROP = 34.0;

static BOOL SC16Enabled(void)
{
    return [UIDevice.currentDevice.systemVersion hasPrefix:@"16."];
}

static void SC16CropWindow(UIWindow *window)
{
    if (!window || !SC16Enabled())
        return;

    if (window.hidden || window.alpha <= 0.0)
        return;

    UIViewController *vc = window.rootViewController;
    UIView *rootView = vc.view;

    if (!rootView)
        return;

    CGRect bounds = rootView.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    /*
     * DỌC
     *
     * 34 trên
     * 34 dưới
     */
    if (height > width)
    {
        top = SC16_CROP;
        bottom = SC16_CROP;
    }
    /*
     * NGANG
     *
     * 34 trái
     * 34 phải
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

    /*
     * Xóa crop cũ.
     */
    rootView.layer.mask = nil;

    /*
     * Không thay đổi:
     *
     * frame
     * bounds
     * center
     * transform
     * safeArea
     */
    CGRect visibleRect = CGRectMake(
        left,
        top,
        cropWidth,
        cropHeight
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

    rootView.layer.mask = mask;
}

static void SC16ApplyAll(void)
{
    if (!SC16Enabled())
        return;

    UIApplication *app =
        UIApplication.sharedApplication;

    for (UIScene *scene in app.connectedScenes)
    {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *ws =
            (UIWindowScene *)scene;

        if (ws.activationState ==
            UISceneActivationStateUnattached)
            continue;

        for (UIWindow *window in ws.windows)
        {
            SC16CropWindow(window);
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
            SC16CropWindow(window);
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
                SC16ApplyAll();

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(0.5 * NSEC_PER_SEC)
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
