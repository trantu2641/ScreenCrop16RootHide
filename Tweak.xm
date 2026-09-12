#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;
static CGFloat const SC16_CORNER_RADIUS = 2.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

/*
 * Các window này không được crop.
 * Đặc biệt keyboard/status bar nếu crop sẽ gây
 * lỗi hiển thị, đen màn hình hoặc Safe Mode.
 */
static BOOL SC16IsExcludedWindow(UIWindow *window) {
    if (!window)
        return YES;

    NSString *className = NSStringFromClass(window.class);

    if ([className containsString:@"UITextEffectsWindow"])
        return YES;

    if ([className containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([className containsString:@"Keyboard"])
        return YES;

    if ([className containsString:@"StatusBar"])
        return YES;

    if ([className containsString:@"_UIStatusBar"])
        return YES;

    if ([className containsString:@"UIRemoteKeyboard"])
        return YES;

    return NO;
}

/*
 * Chỉ xử lý window thuộc màn hình hiện tại.
 */
static CGRect SC16CurrentScreenBounds(UIWindow *window) {
    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    return screen.bounds;
}

/*
 * Scale đồng đều.
 *
 * Không scale X/Y riêng.
 * Tỷ lệ giống nhau nên hình không bị méo.
 */
static CGFloat SC16UniformScale(CGRect original,
                                CGFloat visibleWidth,
                                CGFloat visibleHeight) {
    CGFloat width = CGRectGetWidth(original);
    CGFloat height = CGRectGetHeight(original);

    if (width <= 0.0 || height <= 0.0)
        return 1.0;

    CGFloat sx = visibleWidth / width;
    CGFloat sy = visibleHeight / height;

    return MIN(sx, sy);
}

/*
 * Lấy vùng hiển thị sau khi bỏ 34px trên + 34px dưới.
 *
 * Quan trọng:
 * Không dùng giá trị cố định theo portrait.
 * Khi xoay màn hình, bounds được lấy lại từ UIScreen.
 */
static CGRect SC16VisibleRectForWindow(UIWindow *window) {
    CGRect screenBounds = SC16CurrentScreenBounds(window);

    CGFloat screenWidth = CGRectGetWidth(screenBounds);
    CGFloat screenHeight = CGRectGetHeight(screenBounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0)
        return CGRectZero;

    CGFloat top = SC16_TOP_CROP;
    CGFloat bottom = SC16_BOTTOM_CROP;

    /*
     * Luôn crop theo cạnh trên/dưới của
     * coordinate space hiện tại.
     */
    CGFloat visibleHeight = screenHeight - top - bottom;

    if (visibleHeight <= 0.0)
        return CGRectZero;

    return CGRectMake(
        0.0,
        top,
        screenWidth,
        visibleHeight
    );
}

/*
 * Apply transform theo vùng crop.
 *
 * Window vẫn giữ frame màn hình.
 * Nội dung được scale đồng đều và đặt giữa.
 *
 * Không thay đổi frame trong lúc UIKit đang layout.
 */
static void SC16ApplyTransform(UIWindow *window) {
    if (!window)
        return;

    if (SC16IsExcludedWindow(window))
        return;

    CGRect screenBounds = SC16CurrentScreenBounds(window);
    CGRect visibleRect = SC16VisibleRectForWindow(window);

    if (CGRectIsEmpty(screenBounds) ||
        CGRectIsEmpty(visibleRect))
        return;

    CGFloat screenWidth = CGRectGetWidth(screenBounds);
    CGFloat screenHeight = CGRectGetHeight(screenBounds);

    CGFloat visibleWidth = CGRectGetWidth(visibleRect);
    CGFloat visibleHeight = CGRectGetHeight(visibleRect);

    if (screenWidth <= 0.0 ||
        screenHeight <= 0.0 ||
        visibleWidth <= 0.0 ||
        visibleHeight <= 0.0)
        return;

    /*
     * Đưa window về trạng thái chuẩn trước khi tính.
     */
    window.transform = CGAffineTransformIdentity;

    /*
     * Window full-screen.
     *
     * Không thay đổi frame/bounds của window,
     * tránh làm UIKit tính safe-area sai.
     */
    CGRect frame = screenBounds;

    window.frame = frame;

    /*
     * Scale đồng nhất.
     *
     * Vì visibleWidth == screenWidth nên scale
     * chủ yếu dựa trên chiều cao.
     */
    CGFloat scale =
        SC16UniformScale(
            screenBounds,
            visibleWidth,
            visibleHeight
        );

    /*
     * Scale tối đa không vượt quá 1.
     */
    if (scale > 1.0)
        scale = 1.0;

    if (scale <= 0.0)
        scale = 1.0;

    /*
     * Nội dung được scale quanh tâm window.
     *
     * Không kéo lệch lên/xuống.
     */
    window.transform =
        CGAffineTransformMakeScale(scale, scale);
}

/*
 * Crop thật bằng mask ở cấp UIWindow.
 *
 * Đây là phần giúp vùng trên/dưới bị loại khỏi
 * vùng render của window thay vì chỉ đổi frame.
 */
static void SC16ApplyMask(UIWindow *window) {
    if (!window)
        return;

    if (SC16IsExcludedWindow(window))
        return;

    CGRect screenBounds = SC16CurrentScreenBounds(window);

    CGFloat width = CGRectGetWidth(screenBounds);
    CGFloat height = CGRectGetHeight(screenBounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGFloat top = SC16_TOP_CROP;
    CGFloat bottom = SC16_BOTTOM_CROP;

    CGFloat visibleHeight =
        height - top - bottom;

    if (visibleHeight <= 0.0)
        return;

    /*
     * Mask theo coordinate space của window.
     */
    CAShapeLayer *mask =
        (CAShapeLayer *)window.layer.mask;

    if (!mask) {
        mask = [CAShapeLayer layer];
        window.layer.mask = mask;
    }

    CGRect maskBounds = CGRectMake(
        0.0,
        top,
        width,
        visibleHeight
    );

    /*
     * Bo góc rất nhẹ: 2.0.
     */
    UIBezierPath *path =
        [UIBezierPath
            bezierPathWithRoundedRect:maskBounds
            cornerRadius:SC16_CORNER_RADIUS];

    mask.frame = window.bounds;
    mask.path = path.CGPath;

    /*
     * Không để mask tạo thêm transform.
     */
    mask.contentsScale =
        window.screen.scale;
}

/*
 * Bo góc tổng thể của window.
 *
 * 2.0 theo yêu cầu.
 */
static void SC16ApplyCorners(UIWindow *window) {
    if (!window)
        return;

    if (SC16IsExcludedWindow(window))
        return;

    window.layer.cornerRadius =
        SC16_CORNER_RADIUS;

    window.layer.masksToBounds = NO;
}

/*
 * Apply toàn bộ nhưng KHÔNG gọi layoutIfNeeded.
 *
 * Tránh vòng lặp:
 * setFrame -> layout -> setFrame -> ...
 */
static void SC16ApplyWindow(UIWindow *window) {
    if (!window)
        return;

    if (window.hidden)
        return;

    if (window.alpha <= 0.0)
        return;

    if (SC16IsExcludedWindow(window))
        return;

    SC16ApplyTransform(window);
    SC16ApplyMask(window);
    SC16ApplyCorners(window);
}

/*
 * Apply cho scene.
 *
 * scene.windows là API chính xác trên iOS 15+.
 */
static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled() || !scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows) {
        if (!window.hidden)
            SC16ApplyWindow(window);
    }
}

/*
 * Apply toàn bộ scene.
 */
static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    UIApplication *app =
        UIApplication.sharedApplication;

    NSSet<UIScene *> *scenes =
        app.connectedScenes;

    for (UIScene *scene in scenes) {

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
 * Re-apply sau rotation.
 *
 * Dùng UIDeviceOrientationDidChangeNotification
 * vì UIWindowSceneDidUpdateNotification không tồn tại
 * trong SDK đang build.
 */
static void SC16ReapplyAfterRotation(void) {
    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();

            /*
             * UIKit đôi khi hoàn tất layout rotation
             * ở main-loop kế tiếp.
             */
            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();
                }
            );
        }
    );
}

/*
 * Reapply khi app active.
 */
static void SC16ReapplyAfterActivation(void) {
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

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyWindow(window);
        }
    );
}

/*
 * Window từ hidden -> visible.
 */
- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    if (!SC16Enabled() || hidden)
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!window.hidden)
                SC16ApplyWindow(window);
        }
    );
}

/*
 * KHÔNG crop trực tiếp trong setFrame.
 *
 * Chỉ cho UIKit hoàn tất frame trước,
 * sau đó apply ở run-loop kế tiếp.
 */
- (void)setFrame:(CGRect)frame {
    %orig(frame);

    if (!SC16Enabled())
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!window.hidden)
                SC16ApplyWindow(window);
        }
    );
}

%end

%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        /*
         * Initial apply.
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

                SC16ReapplyAfterActivation();
            }];

        /*
         * Scene activate.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

        /*
         * Scene foreground.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneWillEnterForegroundNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

        /*
         * Rotation.
         *
         * Không dùng API notification không tồn tại.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ReapplyAfterRotation();
            }];
    }
}
