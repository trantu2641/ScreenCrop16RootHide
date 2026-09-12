#import <UIKit/UIKit.h>

static CGFloat const SC16_CROP = 34.0;

static BOOL SC16Enabled(void)
{
    return [UIDevice.currentDevice.systemVersion hasPrefix:@"16."];
}

/*
 * Crop thử nghiệm:
 *
 * Dọc:
 *   bỏ 34pt trên + 34pt dưới
 *
 * Ngang:
 *   bỏ 34pt trái + 34pt phải
 *
 * Sau đó ép nội dung vào vùng còn lại.
 *
 * Không dùng CALayer mask.
 */
static void SC16CropWindow(UIWindow *window)
{
    if (!window)
        return;

    if (window.hidden)
        return;

    if (window.alpha <= 0.0)
        return;

    CGRect frame = window.frame;

    CGFloat width = CGRectGetWidth(frame);
    CGFloat height = CGRectGetHeight(frame);

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

    CGFloat newWidth =
        width - left - right;

    CGFloat newHeight =
        height - top - bottom;

    if (newWidth <= 0.0 ||
        newHeight <= 0.0)
        return;

    /*
     * QUAN TRỌNG:
     *
     * Không thay đổi kích thước window.
     *
     * Chỉ ép nội dung của window
     * vào vùng crop.
     */

    UIView *root =
        window.rootViewController.view;

    if (!root)
        return;

    CGRect oldBounds =
        root.bounds;

    /*
     * Lưu lại trạng thái cũ.
     */
    CGFloat oldWidth =
        CGRectGetWidth(oldBounds);

    CGFloat oldHeight =
        CGRectGetHeight(oldBounds);

    if (oldWidth <= 0.0 ||
        oldHeight <= 0.0)
        return;

    /*
     * Vùng hiển thị mới.
     */
    CGRect target =
        CGRectMake(
            left,
            top,
            newWidth,
            newHeight
        );

    /*
     * ÉP ROOT VIEW vào vùng còn lại.
     *
     * Nội dung được scale theo cả X/Y.
     *
     * Vì người dùng cho phép méo hình,
     * không giữ aspect ratio.
     */
    root.frame = target;

    root.bounds =
        CGRectMake(
            0.0,
            0.0,
            oldWidth,
            oldHeight
        );

    /*
     * Ép layer render đúng vùng.
     */
    root.layer.masksToBounds = YES;

    /*
     * Không dùng transform của UIWindow.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Ép layout ngay.
     */
    [root setNeedsLayout];
    [root layoutIfNeeded];
}

/*
 * Apply toàn bộ window hiện tại.
 */
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
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
            continue;

        NSArray<UIWindow *> *windows =
            windowScene.windows;

        for (UIWindow *window in windows)
        {
            SC16CropWindow(window);
        }
    }
}

/*
 * Window mới xuất hiện.
 */
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
            SC16CropWindow(window);
        }
    );
}

%end

/*
 * Khởi động.
 */
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
