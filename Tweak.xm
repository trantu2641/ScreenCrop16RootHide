#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_CROP_PIXELS = 34.0;

static CGFloat SC16CropPoints(UIWindow *window)
{
    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGFloat scale = screen.nativeScale;

    if (scale <= 0.0)
        scale = screen.scale;

    if (scale <= 0.0)
        scale = 1.0;

    return SC16_CROP_PIXELS / scale;
}

static void SC16ApplyCrop(UIWindow *window)
{
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

    CGFloat crop = SC16CropPoints(window);

    if (crop <= 0.0)
        return;

    /*
     * Màn hình DỌC:
     *
     * Cắt:
     * 34 px trên
     * 34 px dưới
     *
     * Không cắt trái/phải.
     *
     * Màn hình NGANG:
     *
     * Cắt:
     * 34 px trái
     * 34 px phải
     *
     * Không cắt trên/dưới.
     */

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    if (width > height)
    {
        /*
         * LANDSCAPE
         */
        left = crop;
        right = crop;
    }
    else
    {
        /*
         * PORTRAIT
         */
        top = crop;
        bottom = crop;
    }

    CGFloat visibleWidth =
        width - left - right;

    CGFloat visibleHeight =
        height - top - bottom;

    if (visibleWidth <= 0.0 ||
        visibleHeight <= 0.0)
        return;

    /*
     * Xóa mask cũ trước khi tạo lại.
     */
    window.layer.mask = nil;

    /*
     * Vùng được phép render.
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
     * Crop thật bằng Core Animation.
     */
    window.layer.mask = mask;
}

%hook UIWindow

- (void)makeKeyAndVisible
{
    %orig;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyCrop(self);
        }
    );
}

%end

%ctor
{
    @autoreleasepool
    {
        NSString *version =
            UIDevice.currentDevice.systemVersion;

        /*
         * Chỉ chạy iOS 16.x.
         */
        if (![version hasPrefix:@"16."])
            return;

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                NSArray<UIWindow *> *windows =
                    UIApplication.sharedApplication.windows;

                for (UIWindow *window in windows)
                {
                    SC16ApplyCrop(window);
                }
            }
        );
    }
}
