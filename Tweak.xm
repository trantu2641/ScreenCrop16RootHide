#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

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
 * ==========================================
 * MASK
 * ==========================================
 *
 * Window vẫn giữ nguyên kích thước thật.
 *
 * Chỉ vùng:
 *
 * DỌC:
 * 34px trên
 * 2710px nội dung
 * 34px dưới
 *
 * được hiển thị.
 */
static void SC16ApplyMask(UIWindow *window) {

    if (!window)
        return;

    CGFloat width = CGRectGetWidth(window.bounds);
    CGFloat height = CGRectGetHeight(window.bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    BOOL portrait = SC16IsPortrait(window);

    CGRect visibleRect;

    if (portrait) {

        visibleRect = CGRectMake(
            0.0,
            SC16_TOP_CROP,
            width,
            height
                - SC16_TOP_CROP
                - SC16_BOTTOM_CROP
        );

    } else {

        /*
         * Ngang:
         *
         * Không dùng top/bottom theo
         * coordinate dọc.
         *
         * Crop hai cạnh tương ứng của
         * màn hình ngang.
         */
        visibleRect = CGRectMake(
            SC16_TOP_CROP,
            0.0,
            width
                - SC16_TOP_CROP
                - SC16_BOTTOM_CROP,
            height
        );
    }

    if (visibleRect.size.width <= 0.0 ||
        visibleRect.size.height <= 0.0)
        return;

    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame = window.bounds;

    mask.path =
        [UIBezierPath
            bezierPathWithRect:visibleRect].CGPath;

    window.layer.mask = mask;
}


/*
 * ==========================================
 * SAFE AREA
 * ==========================================
 *
 * Đây mới là phần quan trọng.
 *
 * Không di chuyển rootView.
 * Không resize rootView.
 *
 * Chỉ nói cho UIKit:
 *
 * "Vùng an toàn bắt đầu từ 34px
 *  và kết thúc trước 34px cuối."
 *
 * Nếu thiết bị thật đang có safe-area
 * lớn hơn 34px, additionalSafeAreaInsets
 * sẽ bù ngược lại.
 */
static void SC16ApplySafeArea(
    UIViewController *controller,
    UIWindow *window
) {

    if (!controller || !window)
        return;

    UIView *view = controller.view;

    if (!view)
        return;

    CGFloat width = CGRectGetWidth(window.bounds);
    CGFloat height = CGRectGetHeight(window.bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    BOOL portrait = SC16IsPortrait(window);

    UIEdgeInsets current =
        view.safeAreaInsets;

    UIEdgeInsets desired;

    if (portrait) {

        /*
         * Muốn safe-area thực tế:
         *
         * top = 34
         * bottom = 34
         */
        desired = UIEdgeInsetsMake(
            SC16_TOP_CROP,
            0.0,
            SC16_BOTTOM_CROP,
            0.0
        );

    } else {

        /*
         * Ngang:
         *
         * crop 34px hai cạnh ngang.
         */
        desired = UIEdgeInsetsMake(
            0.0,
            SC16_TOP_CROP,
            0.0,
            SC16_BOTTOM_CROP
        );
    }


    /*
     * additionalSafeAreaInsets = desired - current
     *
     * Như vậy nếu iOS đang cho safe-area:
     *
     * top = 59
     *
     * ta có:
     *
     * additional = 34 - 59 = -25
     *
     * => effective safe-area = 34
     *
     * Không phải cộng thêm 34 vào notch.
     */
    UIEdgeInsets additional;

    additional.top =
        desired.top - current.top;

    additional.left =
        desired.left - current.left;

    additional.bottom =
        desired.bottom - current.bottom;

    additional.right =
        desired.right - current.right;


    /*
     * Giới hạn để tránh giá trị cực đoan
     * khi UIKit đang transition.
     */
    additional.top =
        MAX(-100.0, MIN(100.0, additional.top));

    additional.left =
        MAX(-100.0, MIN(100.0, additional.left));

    additional.bottom =
        MAX(-100.0, MIN(100.0, additional.bottom));

    additional.right =
        MAX(-100.0, MIN(100.0, additional.right));


    controller.additionalSafeAreaInsets =
        additional;
}


/*
 * ==========================================
 * APPLY
 * ==========================================
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

    UIViewController *root =
        window.rootViewController;

    if (!root)
        return;

    /*
     * QUAN TRỌNG:
     *
     * KHÔNG:
     *   window.frame = ...
     *
     * KHÔNG:
     *   root.view.frame = ...
     *
     * KHÔNG:
     *   root.view.transform = ...
     *
     * Chỉ mask + safe-area.
     */

    SC16ApplySafeArea(root, window);
    SC16ApplyMask(window);
}


/*
 * ==========================================
 * APPLY ALL SCENES
 * ==========================================
 */
static void SC16ApplyAllScenes(void) {

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

            if (window.hidden)
                continue;

            if (window.windowLevel !=
                UIWindowLevelNormal)
                continue;

            SC16ApplyWindow(window);
        }
    }
}


/*
 * ==========================================
 * UIWindow
 * ==========================================
 *
 * Chỉ hook những điểm cần thiết.
 *
 * KHÔNG hook setFrame.
 * KHÔNG hook layoutSubviews.
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
 * ==========================================
 * UIViewController
 * ==========================================
 *
 * Chỉ apply khi root controller xuất hiện
 * hoặc safe-area thực sự thay đổi.
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

            if (!window)
                return;

            if (window.rootViewController !=
                controller)
                return;

            SC16ApplyWindow(window);
        }
    );
}

- (void)viewSafeAreaInsetsDidChange {

    %orig;

    if (!SC16Enabled())
        return;

    UIViewController *controller = self;

    UIWindow *window =
        controller.view.window;

    if (!window)
        return;

    if (window.rootViewController !=
        controller)
        return;

    /*
     * UIKit vừa thay đổi safe-area.
     *
     * Apply lại một lần ở main queue.
     *
     * Không dùng layoutSubviews nên
     * không tạo vòng lặp layout liên tục.
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
 * ==========================================
 * ORIENTATION / SCENE
 * ==========================================
 */
%ctor {

    @autoreleasepool {

        if (!SC16Enabled())
            return;


        /*
         * Initial.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ApplyAllScenes();
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

                SC16ApplyAllScenes();
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
                ^(__unused NSNotification *notification) {

                SC16ApplyAllScenes();
            }];


        /*
         * Xoay màn hình.
         *
         * Không chỉnh geometry của scene.
         *
         * Chờ UIKit hoàn tất transition
         * rồi lấy bounds/orientation mới.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(__unused NSNotification *notification) {

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)
                        (0.20 *
                         NSEC_PER_SEC)
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAllScenes();
                    }
                );
            }];
    }
}
