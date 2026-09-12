#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_CROP = 34.0;

static BOOL SC16Enabled(void)
{
    return [UIDevice.currentDevice.systemVersion hasPrefix:@"16."];
}

/*
 * Tạo viewport crop và dịch nội dung.
 *
 * DỌC:
 *   crop 34 trên
 *   crop 34 dưới
 *
 * NGANG:
 *   crop 34 trái
 *   crop 34 phải
 *
 * UIWindow KHÔNG bị resize.
 * UIWindow KHÔNG bị đổi frame.
 * UIWindow KHÔNG bị đổi transform.
 */
static void SC16Apply(UIWindow *window)
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

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    /*
     * PORTRAIT
     *
     * 34 trên / 34 dưới
     */
    if (height > width)
    {
        top = SC16_CROP;
        bottom = SC16_CROP;
    }
    /*
     * LANDSCAPE
     *
     * 34 trái / 34 phải
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
     * Lưu root view.
     */
    UIView *root =
        window.rootViewController.view;

    if (!root)
        return;

    /*
     * QUAN TRỌNG:
     *
     * Không thay đổi window.frame/bounds.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Reset transform của root.
     *
     * Bản test này dùng transform để dịch
     * nội dung vào vùng crop.
     */
    root.transform =
        CGAffineTransformIdentity;

    /*
     * Đưa nội dung về phía vùng đã crop.
     *
     * Dọc:
     *   nội dung dịch lên 34pt
     *
     * Ngang:
     *   nội dung dịch sang trái 34pt
     *
     * Sau đó viewport mask cắt phần thừa.
     */
    if (height > width)
    {
        root.transform =
            CGAffineTransformMakeTranslation(
                0.0,
                -top
            );
    }
    else
    {
        root.transform =
            CGAffineTransformMakeTranslation(
                -left,
                0.0
            );
    }

    /*
     * Tạo viewport.
     *
     * Đây mới là vùng được phép render.
     */
    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame = bounds;

    CGRect visibleRect =
        CGRectMake(
            CGRectGetMinX(bounds) + left,
            CGRectGetMinY(bounds) + top,
            cropWidth,
            cropHeight
        );

    CGPathRef path =
        CGPathCreateWithRect(
            visibleRect,
            NULL
        );

    mask.path = path;

    CGPathRelease(path);

    /*
     * Crop thật ở tầng UIWindow.
     */
    window.layer.mask = mask;

    /*
     * Đảm bảo UIKit cập nhật ngay.
     */
    [root setNeedsLayout];
    [root setNeedsDisplay];

    /*
     * Không layoutIfNeeded ở đây.
     *
     * Tránh UIKit tự thay đổi geometry trong lúc
     * chúng ta đang crop.
     */
}

/*
 * Apply các UIWindow thuộc scene.
 */
static void SC16ApplyScene(UIWindowScene *scene)
{
    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows)
    {
        SC16Apply(window);
    }
}

/*
 * Apply toàn bộ scene.
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

        SC16ApplyScene(
            (UIWindowScene *)scene
        );
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
            SC16Apply(window);
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
            SC16Apply(window);
        }
    );
}

%end

/*
 * Constructor.
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
                /*
                 * Lần 1
                 */
                SC16ApplyAll();

                /*
                 * Lần 2 sau khi UIKit hoàn thành
                 * việc tạo root/window.
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
