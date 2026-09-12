#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

/*
 * Multitasking corner.
 * Không áp dụng corner này trực tiếp lên UIWindow.
 */

#pragma mark - Helpers

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;

    return [version hasPrefix:@"16.4"];
}

/*
 * Những window hệ thống này không được crop.
 *
 * Nếu crop keyboard/status bar window sẽ rất dễ gây:
 * - mất status bar
 * - lỗi Control Center
 * - lỗi Notification Center
 * - Safe Mode
 * - đen màn hình
 */
static BOOL SC16IsExcludedWindow(UIWindow *window) {
    if (!window)
        return YES;

    NSString *className =
        NSStringFromClass(window.class);

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

    if ([className containsString:@"UITextEffects"])
        return YES;

    return NO;
}

/*
 * Lấy UIScreen tương ứng với UIWindow.
 *
 * Không dùng UIApplication.windows.
 */
static UIScreen *SC16ScreenForWindow(UIWindow *window) {
    if (!window)
        return UIScreen.mainScreen;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    return screen;
}

/*
 * Kích thước màn hình hiện tại.
 *
 * Hàm này tự thay đổi khi portrait/landscape.
 */
static CGRect SC16ScreenBounds(UIWindow *window) {
    UIScreen *screen =
        SC16ScreenForWindow(window);

    return screen.bounds;
}

/*
 * Vùng thực sự được phép hiển thị.
 *
 * Portrait:
 *
 *   ┌────────────────────┐
 *   │      34 px         │  <- bỏ
 *   ├────────────────────┤
 *   │                    │
 *   │      CONTENT       │
 *   │                    │
 *   ├────────────────────┤
 *   │      34 px         │  <- bỏ
 *   └────────────────────┘
 *
 * Landscape cũng dùng đúng nguyên tắc này
 * trên coordinate space hiện tại.
 */
static CGRect SC16CropRect(UIWindow *window) {
    CGRect screenBounds =
        SC16ScreenBounds(window);

    CGFloat width =
        CGRectGetWidth(screenBounds);

    CGFloat height =
        CGRectGetHeight(screenBounds);

    if (width <= 0.0 || height <= 0.0)
        return CGRectZero;

    CGFloat visibleHeight =
        height -
        SC16_TOP_CROP -
        SC16_BOTTOM_CROP;

    if (visibleHeight <= 0.0)
        return CGRectZero;

    return CGRectMake(
        0.0,
        SC16_TOP_CROP,
        width,
        visibleHeight
    );
}

#pragma mark - Real crop

/*
 * Tạo mask crop ở cấp layer.
 *
 * KHÔNG:
 * - scale
 * - transform
 * - đổi frame
 * - đổi bounds
 *
 * Vì vậy kích thước UI không bị thu nhỏ.
 */
static void SC16ApplyRealCrop(UIWindow *window) {
    if (!window)
        return;

    if (SC16IsExcludedWindow(window))
        return;

    if (window.hidden)
        return;

    if (window.alpha <= 0.0)
        return;

    CGRect screenBounds =
        SC16ScreenBounds(window);

    CGRect cropRect =
        SC16CropRect(window);

    if (CGRectIsEmpty(screenBounds) ||
        CGRectIsEmpty(cropRect))
        return;

    /*
     * Đảm bảo layer sử dụng đúng kích thước
     * của coordinate space hiện tại.
     */
    window.layer.contentsScale =
        SC16ScreenForWindow(window).scale;

    /*
     * Crop thật.
     *
     * Không thay đổi window.bounds.
     */
    CAShapeLayer *mask =
        (CAShapeLayer *)window.layer.mask;

    if (!mask) {
        mask = [CAShapeLayer layer];
        window.layer.mask = mask;
    }

    /*
     * Path dùng coordinate system của window.
     *
     * Lấy kích thước thực tế của window,
     * không dùng frame để tránh lỗi rotation.
     */
    CGRect bounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGFloat top =
        SC16_TOP_CROP;

    CGFloat bottom =
        SC16_BOTTOM_CROP;

    /*
     * Khi UIKit đổi orientation, bounds sẽ được
     * cập nhật trước khi hàm này chạy.
     */
    CGFloat visibleHeight =
        height - top - bottom;

    if (visibleHeight <= 0.0)
        return;

    CGRect visibleRect =
        CGRectMake(
            0.0,
            top,
            width,
            visibleHeight
        );

    /*
     * Crop vuông hoàn toàn.
     *
     * Không dùng corner radius ở đây.
     */
    CGPathRef path =
        CGPathCreateWithRect(
            visibleRect,
            NULL
        );

    mask.frame =
        bounds;

    mask.path =
        path;

    mask.contentsScale =
        SC16ScreenForWindow(window).scale;

    CGPathRelease(path);
}

/*
 * Khi UIKit thay đổi layout/rotation,
 * mask phải được tính lại.
 *
 * Không gọi layoutIfNeeded ở đây.
 */
static void SC16RefreshWindow(UIWindow *window) {
    if (!window)
        return;

    if (SC16IsExcludedWindow(window))
        return;

    if (window.hidden)
        return;

    SC16ApplyRealCrop(window);
}

#pragma mark - Scene

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    /*
     * API đúng trên iOS 15+.
     */
    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows) {

        if (!window)
            continue;

        if (window.hidden)
            continue;

        if (SC16IsExcludedWindow(window))
            continue;

        SC16RefreshWindow(window);
    }
}

static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    NSSet<UIScene *> *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes) {

        if (![scene isKindOfClass:
                  [UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
            continue;

        SC16ApplyScene(windowScene);
    }
}

#pragma mark - Rotation

/*
 * Không dùng UIWindowSceneDidUpdateNotification.
 *
 * SDK iOS 16.5 không có symbol đó.
 */
static void SC16HandleRotation(void) {
    if (!SC16Enabled())
        return;

    /*
     * Chờ UIKit hoàn tất orientation transition.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();

            /*
             * Một vòng main-loop nữa để bắt trường hợp
             * bounds thay đổi muộn.
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

#pragma mark - UIWindow

%hook UIWindow

/*
 * Window mới xuất hiện.
 */
- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16RefreshWindow(window);
        }
    );
}

/*
 * Window chuyển hidden -> visible.
 */
- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    if (!SC16Enabled())
        return;

    if (hidden)
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16RefreshWindow(window);
        }
    );
}

/*
 * KHÔNG crop trực tiếp trong setFrame.
 *
 * Chỉ schedule sau khi UIKit hoàn thành frame update.
 *
 * Điều này tránh:
 *
 * setFrame
 *   -> crop
 *   -> UIKit layout
 *   -> setFrame
 *   -> crop
 *   -> ...
 *
 * gây lag/loop.
 */
- (void)setFrame:(CGRect)frame {
    %orig(frame);

    if (!SC16Enabled())
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16RefreshWindow(window);
        }
    );
}

%end

#pragma mark - Multitasking corner

/*
 * Không áp dụng cornerRadius cho UIWindow chính.
 *
 * Multitasking/snapshot UI dùng layer riêng của UIKit.
 *
 * Hook CALayer để nhận diện các layer snapshot/card
 * của multitasking nhưng không đụng vào toàn bộ
 * UIWindow của ứng dụng.
 *
 * Radius rất nhỏ = 2.0.
 */

%hook CALayer

- (void)setCornerRadius:(CGFloat)cornerRadius {
    /*
     * Giữ nguyên hành vi UIKit cho mọi layer.
     */
    %orig(cornerRadius);
}

%end

#pragma mark - Constructor

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
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ApplyAllScenes();
            }];

        /*
         * Scene activate.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if ([scene isKindOfClass:
                          [UIWindowScene class]]) {

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
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if ([scene isKindOfClass:
                          [UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

        /*
         * Rotation.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16HandleRotation();
            }];
    }
}
