#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

/*
 * Guard để UIKit không gọi lại quá nhiều lần.
 */
static BOOL SC16Applying = NO;

/*
 * Lấy window đang thực sự hiển thị.
 */
static UIWindow *SC16ActiveWindowForScene(UIWindowScene *scene) {
    if (!scene)
        return nil;

    UIWindow *candidate = nil;

    for (UIWindow *window in scene.windows) {
        if (window.hidden)
            continue;

        if (window.alpha <= 0.01)
            continue;

        /*
         * Ưu tiên window key.
         */
        if (window.isKeyWindow)
            return window;

        /*
         * Không lấy keyboard/system windows.
         */
        NSString *className = NSStringFromClass(window.class);

        if ([className containsString:@"Keyboard"])
            continue;

        if ([className containsString:@"TextEffects"])
            continue;

        candidate = window;
    }

    return candidate;
}

/*
 * Cập nhật safe-area để UIKit biết rằng 34px trên
 * và 34px dưới không còn nằm trong vùng sử dụng.
 */
static void SC16UpdateSafeArea(UIWindow *window) {
    if (!window)
        return;

    UIWindowScene *scene = window.windowScene;
    if (!scene)
        return;

    CGRect bounds = scene.coordinateSpace.bounds;

    CGFloat width  = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    /*
     * Với màn hình dọc:
     *
     * 1284 x 2778
     *
     * crop:
     * top    = 34
     * bottom = 34
     *
     * vùng sử dụng:
     * 1284 x 2710
     */
    UIEdgeInsets insets =
        UIEdgeInsetsMake(
            SC16_TOP_CROP,
            0.0,
            SC16_BOTTOM_CROP,
            0.0
        );

    /*
     * Không thay đổi frame window.
     *
     * Thay vào đó dùng additionalSafeAreaInsets
     * để UIKit layout nội dung trong vùng đã crop.
     */
    UIViewController *root = window.rootViewController;

    if (root) {
        root.additionalSafeAreaInsets = insets;
    }
}

/*
 * Tạo mask CLIPPING thật sự.
 *
 * Nội dung nằm ngoài vùng:
 *
 *     34px
 *     ┌───────────────┐
 *     │               │
 *     │   APP CONTENT │
 *     │               │
 *     └───────────────┘
 *     34px
 *
 * sẽ không được render ra window.
 */
static void SC16ApplyMask(UIWindow *window) {
    if (!window)
        return;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return;

    CGRect bounds = scene.coordinateSpace.bounds;

    CGFloat width  = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    if (height <= SC16_TOP_CROP + SC16_BOTTOM_CROP)
        return;

    /*
     * Window bounds giữ nguyên.
     * Chỉ thay đổi vùng được phép render.
     */
    CGRect cropRect = CGRectMake(
        0.0,
        SC16_TOP_CROP,
        width,
        height - SC16_TOP_CROP - SC16_BOTTOM_CROP
    );

    /*
     * CAShapeLayer mask clip trực tiếp nội dung window.
     */
    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame = window.bounds;

    mask.path =
        [UIBezierPath bezierPathWithRect:cropRect].CGPath;

    window.layer.mask = mask;

    /*
     * Không dùng transform.
     */
    window.transform = CGAffineTransformIdentity;
}

/*
 * Áp dụng toàn bộ crop.
 */
static void SC16ApplyWindow(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (SC16Applying)
        return;

    SC16Applying = YES;

    /*
     * UIKit layout trước.
     */
    [window layoutIfNeeded];

    /*
     * Clip thật.
     */
    SC16ApplyMask(window);

    /*
     * Sau đó mới cập nhật safe area.
     */
    SC16UpdateSafeArea(window);

    SC16Applying = NO;
}

/*
 * Áp dụng cho scene hiện tại.
 */
static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    UIWindow *window =
        SC16ActiveWindowForScene(scene);

    if (window) {
        SC16ApplyWindow(window);
    }
}

/*
 * Tìm tất cả UIWindowScene đang hoạt động.
 */
static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    UIApplication *app =
        UIApplication.sharedApplication;

    for (UIScene *scene in app.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
            continue;

        SC16ApplyScene(windowScene);
    }
}

/*
 * Khi orientation thay đổi.
 *
 * Quan trọng:
 * KHÔNG đổi frame.
 * KHÔNG đổi transform.
 *
 * Chỉ tạo lại crop mask dựa trên kích thước
 * scene hiện tại.
 */
static void SC16OrientationChanged(void) {
    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();
        }
    );
}

%hook UIWindow

/*
 * Window xuất hiện.
 */
- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyWindow(self);
        }
    );
}

%end

%hook UIViewController

/*
 * Sau khi UIKit layout lại root controller,
 * áp dụng lại safe area.
 *
 * Không hook setFrame của UIWindow nữa.
 */
- (void)viewDidLayoutSubviews {
    %orig;

    if (!SC16Enabled())
        return;

    UIView *view = self.view;

    UIWindow *window = view.window;

    if (!window)
        return;

    if (self == window.rootViewController) {
        SC16ApplyWindow(window);
    }
}

%end

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
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ApplyAllScenes();
            }];

        /*
         * Scene active.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

        /*
         * Orientation.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16OrientationChanged();
            }];

        /*
         * Screen/window layout thay đổi.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIWindowDidBecomeVisibleNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIWindow *window = notification.object;

                if ([window isKindOfClass:[UIWindow class]]) {

                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{
                            SC16ApplyWindow(window);
                        }
                    );
                }
            }];
    }
}
