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


#pragma mark - Enable

static BOOL SC16Enabled(void)
{
    NSString *version =
        UIDevice.currentDevice.systemVersion;

    return [version hasPrefix:@"16."];
}


#pragma mark - Crop Window

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

    CGRect bounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;


    /*
     * Xác định orientation trực tiếp
     * từ bounds của window.
     */
    BOOL landscape =
        width > height;


    /*
     * Xóa mask cũ.
     */
    window.layer.mask = nil;


    /*
     * Cắt hai đầu.
     */
    CGFloat left   = 0.0;
    CGFloat right  = 0.0;
    CGFloat top    = 0.0;
    CGFloat bottom = 0.0;

    if (landscape)
    {
        /*
         * NGANG
         *
         * 34 trái
         * 34 phải
         */
        left  = SC16_CROP;
        right = SC16_CROP;
    }
    else
    {
        /*
         * DỌC
         *
         * 34 trên
         * 34 dưới
         */
        top    = SC16_CROP;
        bottom = SC16_CROP;
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
     * Mask vùng thực sự được hiển thị.
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


    window.layer.mask =
        mask;


    /*
     * ------------------------------------------------
     * ĐẨY CONTENT VÀO VÙNG CROP
     * ------------------------------------------------
     *
     * Không thay đổi UIWindow frame/bounds.
     *
     * Chỉ tác động root view.
     */

    UIView *content =
        window.rootViewController.view;

    if (!content)
        return;


    /*
     * Xóa transform cũ trước khi áp dụng.
     */
    content.layer.transform =
        CATransform3DIdentity;


    if (landscape)
    {
        /*
         * NGANG:
         *
         * Crop trái 34
         *
         * Đẩy content sang phải 34.
         */
        content.layer.transform =
            CATransform3DMakeTranslation(
                SC16_CROP,
                0.0,
                0.0
            );
    }
    else
    {
        /*
         * DỌC:
         *
         * Crop trên 34
         *
         * Đẩy content xuống 34.
         */
        content.layer.transform =
            CATransform3DMakeTranslation(
                0.0,
                SC16_CROP,
                0.0
            );
    }
}


#pragma mark - Apply All Windows

static void SC16ApplyAllWindows(void)
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
            if (!window)
                continue;

            SC16ApplyCrop(window);
        }
    }
}


#pragma mark - UIWindow Hook

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
                 * Đợi UIKit tạo window.
                 */
                SC16ApplyAllWindows();


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
                        SC16ApplyAllWindows();
                    }
                );
            }
        );
    }
}
