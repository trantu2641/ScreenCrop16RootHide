#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Configuration

static const CGFloat SC16_TOP_CROP = 34.0;
static const CGFloat SC16_BOTTOM_CROP = 34.0;
static const CGFloat SC16_MULTITASK_RADIUS = 2.0;

#pragma mark - Helpers

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

/*
 * Những UIWindow này thuộc UIKit/System UI.
 * Không crop để tránh phá:
 *
 * - Status Bar
 * - Keyboard
 * - Control Centre
 * - Notification
 * - các overlay của hệ thống
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

    if ([className containsString:@"TextEffects"])
        return YES;

    if ([className containsString:@"RemoteKeyboard"])
        return YES;

    return NO;
}

static BOOL SC16ValidWindow(UIWindow *window) {
    if (!window)
        return NO;

    if (window.hidden)
        return NO;

    if (window.alpha <= 0.0)
        return NO;

    if (SC16IsExcludedWindow(window))
        return NO;

    if (!window.screen)
        return NO;

    return YES;
}

#pragma mark - Crop Mask

/*
 * Crop bằng CALayer mask thay vì thay đổi:
 *
 *     window.bounds
 *     window.frame
 *     window.transform
 *
 * Vì vậy UIKit vẫn giữ nguyên coordinate space,
 * không scale và không đẩy safe-area/layout xuống.
 *
 * Phần ngoài vùng mask thực sự không được render.
 */
static void SC16ApplyCropMask(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!SC16ValidWindow(window))
        return;

    CGRect bounds = window.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    if (height <= (SC16_TOP_CROP + SC16_BOTTOM_CROP))
        return;

    /*
     * Crop theo chiều Y của chính UIWindow.
     *
     * Quan trọng:
     * Không sử dụng UIScreen.bounds để quyết định
     * chiều crop.
     *
     * Vì vậy khi rotation:
     *
     * Portrait:
     *   top    = 34
     *   bottom = 34
     *
     * Landscape:
     *   vẫn crop theo hai đầu màn hình,
     *   không nhầm 1248 thành chiều cần cắt.
     */

    CGFloat visibleHeight =
        height - SC16_TOP_CROP - SC16_BOTTOM_CROP;

    if (visibleHeight <= 0.0)
        return;

    /*
     * Tạo mask theo tọa độ nội bộ của UIWindow.
     *
     * Không resize UIWindow.
     * Không scale nội dung.
     */
    CAShapeLayer *mask =
        [CAShapeLayer layer];

    CGPathRef path =
        CGPathCreateWithRect(
            CGRectMake(
                0.0,
                SC16_TOP_CROP,
                width,
                visibleHeight
            ),
            NULL
        );

    mask.path = path;
    mask.frame = bounds;

    CGPathRelease(path);

    window.layer.mask = mask;
}

#pragma mark - Multitasking Corner

/*
 * Corner radius chỉ áp dụng cho UIWindow của ứng dụng.
 *
 * Không dùng masksToBounds vì có thể làm thay đổi
 * clipping của nội dung/window và gây hiệu ứng phụ.
 *
 * Chỉ đặt cornerRadius = 2.0.
 */
static void SC16ApplyMultitaskCorner(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!SC16ValidWindow(window))
        return;

    window.layer.cornerRadius = SC16_MULTITASK_RADIUS;
    window.layer.masksToBounds = NO;
}

#pragma mark - Apply

static void SC16ApplyWindow(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!SC16ValidWindow(window))
        return;

    /*
     * Không bao giờ thay đổi:
     *
     * window.frame
     * window.bounds
     * window.center
     * window.transform
     *
     * nên không có hiện tượng màn hình bị thu nhỏ.
     */

    SC16ApplyCropMask(window);
    SC16ApplyMultitaskCorner(window);
}

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows) {
        if (SC16ValidWindow(window)) {
            SC16ApplyWindow(window);
        }
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

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        SC16ApplyScene(windowScene);
    }
}

#pragma mark - Reapply

/*
 * Không dùng timer.
 * Không gọi layoutIfNeeded().
 * Không sửa frame trong callback.
 *
 * Chỉ áp dụng lại layer mask sau khi UIKit
 * hoàn tất rotation/scene transition.
 */
static void SC16ReapplyWindowAsync(UIWindow *window) {
    if (!window)
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (SC16ValidWindow(window)) {
                SC16ApplyWindow(window);
            }
        }
    );
}

#pragma mark - UIWindow Hook

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    SC16ReapplyWindowAsync(self);
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    if (!SC16Enabled())
        return;

    if (hidden)
        return;

    SC16ReapplyWindowAsync(self);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(alpha);

    if (!SC16Enabled())
        return;

    if (alpha <= 0.0)
        return;

    SC16ReapplyWindowAsync(self);
}

- (void)didMoveToWindow {
    %orig;

    if (!SC16Enabled())
        return;

    SC16ReapplyWindowAsync(self);
}

%end

#pragma mark - UIApplication / Scene Notifications

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
            queue:[NSOperationQueue mainQueue]
            usingBlock:
            ^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if ([scene
                    isKindOfClass:[UIWindowScene class]]) {

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
            usingBlock:
            ^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if ([scene
                    isKindOfClass:[UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

        /*
         * Rotation.
         *
         * Không sử dụng:
         *
         * UIWindowSceneDidUpdateNotification
         *
         * vì SDK iOS 16.5 không khai báo symbol đó.
         *
         * UIDeviceOrientationDidChangeNotification
         * được dùng chỉ để trigger reapply.
         *
         * Không sửa frame/bounds nên không gây
         * vòng lặp rotation.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:
            ^(__unused NSNotification *notification) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAllScenes();

                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                SC16ApplyAllScenes();
                            }
                        );
                    }
                );
            }];
    }
}
