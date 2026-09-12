#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

static BOOL SC16IsPortrait(UIWindow *window) {
    UIWindowScene *scene = window.windowScene;

    if (scene) {
        UIInterfaceOrientation orientation =
            scene.interfaceOrientation;

        if (orientation != UIInterfaceOrientationUnknown) {
            return UIInterfaceOrientationIsPortrait(orientation);
        }
    }

    return window.bounds.size.height >= window.bounds.size.width;
}

/*
 * Tạo mask để phần crop thực sự không được render.
 */
static void SC16ApplyMask(UIWindow *window) {
    if (!window)
        return;

    CGFloat width = window.bounds.size.width;
    CGFloat height = window.bounds.size.height;

    if (width <= 0.0 || height <= 0.0)
        return;

    BOOL portrait = SC16IsPortrait(window);

    CGFloat top = 0.0;
    CGFloat bottom = 0.0;
    CGFloat left = 0.0;
    CGFloat right = 0.0;

    if (portrait) {
        top = SC16_TOP_CROP;
        bottom = SC16_BOTTOM_CROP;
    } else {
        /*
         * Khi ngang, màn hình đã đổi coordinate system.
         *
         * Crop 34px ở hai cạnh trái/phải để giữ
         * đúng kích thước vùng hiển thị theo màn hình ngang.
         */
        left = SC16_TOP_CROP;
        right = SC16_BOTTOM_CROP;
    }

    CGFloat visibleWidth =
        width - left - right;

    CGFloat visibleHeight =
        height - top - bottom;

    if (visibleWidth <= 0.0 ||
        visibleHeight <= 0.0)
        return;

    UIBezierPath *path =
        [UIBezierPath bezierPathWithRect:
            CGRectMake(
                left,
                top,
                visibleWidth,
                visibleHeight
            )];

    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame = window.bounds;
    mask.path = path.CGPath;
    mask.fillRule = kCAFillRuleNonZero;

    window.layer.mask = mask;
}

/*
 * Di chuyển nội dung mà KHÔNG scale.
 *
 * Dọc:
 *   UI xuống 34px.
 *
 * Ngang:
 *   UI vào vùng crop tương ứng.
 */
static void SC16ApplyContent(UIWindow *window) {
    if (!window)
        return;

    UIViewController *root =
        window.rootViewController;

    if (!root)
        return;

    UIView *view = root.view;

    if (!view)
        return;

    CGFloat width = window.bounds.size.width;
    CGFloat height = window.bounds.size.height;

    if (width <= 0.0 || height <= 0.0)
        return;

    BOOL portrait = SC16IsPortrait(window);

    CGRect frame = window.bounds;

    if (portrait) {
        /*
         * Giữ kích thước nội dung 1:1.
         *
         * Nội dung bắt đầu từ y = 34.
         */
        frame.origin.x = 0.0;
        frame.origin.y = SC16_TOP_CROP;

        frame.size.width = width;
        frame.size.height = height;

    } else {
        /*
         * Ngang:
         * đưa nội dung vào trong vùng đã crop.
         */
        frame.origin.x = SC16_TOP_CROP;
        frame.origin.y = 0.0;

        frame.size.width = width;
        frame.size.height = height;
    }

    /*
     * Không transform.
     * Không scale.
     */
    view.transform =
        CGAffineTransformIdentity;

    view.frame = frame;
}

/*
 * Apply cả crop + content.
 */
static void SC16ApplyWindow(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (window.hidden)
        return;

    if (window.windowLevel != UIWindowLevelNormal)
        return;

    if (!window.rootViewController)
        return;

    /*
     * Mask trước.
     */
    SC16ApplyMask(window);

    /*
     * Sau đó đẩy UI.
     */
    SC16ApplyContent(window);

    [window.rootViewController.view
        setNeedsLayout];

    [window.rootViewController.view
        layoutIfNeeded];
}

static void SC16ApplyAll(void) {
    if (!SC16Enabled())
        return;

    UIApplication *app =
        UIApplication.sharedApplication;

    if (!app)
        return;

    for (UIScene *scene in app.connectedScenes) {

        if (![scene
            isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
            continue;

        for (UIWindow *window in windowScene.windows) {

            if (!window)
                continue;

            SC16ApplyWindow(window);
        }
    }
}

/*
 * =========================
 * UIWindow
 * =========================
 */

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyWindow(window);
        }
    );
}

- (void)setRootViewController:
    (UIViewController *)rootViewController {

    %orig(rootViewController);

    if (!SC16Enabled())
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyWindow(window);
        }
    );
}

%end


/*
 * =========================
 * UIViewController
 * =========================
 *
 * UIKit thường layout lại root view sau
 * khi xoay hoặc thay đổi scene.
 *
 * Vì vậy apply lại SAU layout.
 */

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {

    %orig(animated);

    if (!SC16Enabled())
        return;

    UIViewController *controller = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            UIWindow *window =
                controller.view.window;

            if (window) {
                SC16ApplyWindow(window);
            }
        }
    );
}

- (void)viewDidLayoutSubviews {

    %orig;

    if (!SC16Enabled())
        return;

    UIViewController *controller = self;

    /*
     * Chỉ xử lý root controller của window.
     */
    UIWindow *window =
        controller.view.window;

    if (!window)
        return;

    if (window.rootViewController != controller)
        return;

    /*
     * Không gọi ngay trong layout.
     * Đợi UIKit hoàn tất layout.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyWindow(window);
        }
    );
}

%end


/*
 * =========================
 * Orientation
 * =========================
 */

%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ApplyAll();
            }
        );

        /*
         * App active.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIApplicationDidBecomeActiveNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(__unused NSNotification *notification) {

                SC16ApplyAll();
            }];


        /*
         * Scene active.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if (![scene
                    isKindOfClass:
                    [UIWindowScene class]])
                    return;

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAll();
                    }
                );
            }];


        /*
         * Xoay màn hình.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(__unused NSNotification *notification) {

                /*
                 * Cho UIKit cập nhật orientation,
                 * bounds và safe-area trước.
                 */
                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)
                        (0.20 *
                        NSEC_PER_SEC)
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAll();
                    }
                );
            }];
    }
}
