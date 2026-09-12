#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

static const CGFloat SC16_TOP_CROP_PIXELS = 34.0;
static const CGFloat SC16_BOTTOM_CROP_PIXELS = 34.0;

/*
 * iOS 16.4 only.
 */
static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

#pragma mark - State

static BOOL SC16Updating = NO;

#pragma mark - Pixel conversion

static CGFloat SC16PixelsToPoints(CGFloat pixels, UIScreen *screen) {

    if (!screen)
        screen = UIScreen.mainScreen;

    CGFloat scale = screen.nativeScale;

    if (scale <= 0.0)
        scale = screen.scale;

    if (scale <= 0.0)
        scale = 1.0;

    return pixels / scale;
}

#pragma mark - System window detection

/*
 * KHÔNG crop các window overlay của hệ thống.
 *
 * Nếu mask nhầm Control Center / Notification Center,
 * các gesture và UI hệ thống có thể bị cắt hoặc che.
 */
static BOOL SC16IsSystemOverlayWindow(UIWindow *window) {

    if (!window)
        return YES;

    NSString *className =
        NSStringFromClass(window.class);

    /*
     * Các window hệ thống thường gặp.
     *
     * Không đụng vào chúng.
     */
    NSArray<NSString *> *excludedClasses = @[
        @"UITextEffectsWindow",
        @"UIRemoteKeyboardWindow",
        @"UIInputWindowController",
        @"_UIRemoteKeyboardWindow",
        @"_UIStatusBarWindow",
        @"_UIContextMenuUIControllerWindow",
        @"_UIActivityGroupListViewController",
        @"_UIInterfaceActionGroupContainerView"
    ];

    for (NSString *name in excludedClasses) {

        if ([className isEqualToString:name])
            return YES;

        if ([className containsString:name])
            return YES;
    }

    /*
     * Không crop keyboard / text-effects window.
     */
    if ([className containsString:@"Keyboard"])
        return YES;

    if ([className containsString:@"TextEffects"])
        return YES;

    return NO;
}

#pragma mark - Calculate scale

/*
 * Crop 34 px trên + 34 px dưới.
 *
 * Sau crop:
 *
 *     H - TOP - BOTTOM
 *
 * Scale được tính UNIFORM cho cả X/Y.
 *
 * Không scale X khác Y.
 * Không scale Y khác X.
 *
 * => không méo hình.
 */
static CGFloat SC16UniformScaleForWindow(UIWindow *window) {

    if (!window)
        return 1.0;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGRect bounds = window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return 1.0;

    CGFloat top =
        SC16PixelsToPoints(
            SC16_TOP_CROP_PIXELS,
            screen
        );

    CGFloat bottom =
        SC16PixelsToPoints(
            SC16_BOTTOM_CROP_PIXELS,
            screen
        );

    CGFloat availableHeight =
        height - top - bottom;

    if (availableHeight <= 0.0)
        return 1.0;

    /*
     * Không kéo dãn.
     *
     * Uniform scale.
     */
    CGFloat scale =
        availableHeight / height;

    /*
     * Không bao giờ phóng to.
     */
    if (scale > 1.0)
        scale = 1.0;

    if (scale < 0.01)
        scale = 1.0;

    /*
     * Nếu chiều ngang cần giữ nguyên toàn màn hình,
     * scale này vẫn đồng nhất X/Y.
     */
    (void)width;

    return scale;
}

#pragma mark - Crop mask

static void SC16ApplyCrop(UIWindow *window) {

    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (SC16IsSystemOverlayWindow(window))
        return;

    UIWindowScene *scene =
        window.windowScene;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    UIScreen *screen =
        window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGRect bounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGFloat top =
        SC16PixelsToPoints(
            SC16_TOP_CROP_PIXELS,
            screen
        );

    CGFloat bottom =
        SC16PixelsToPoints(
            SC16_BOTTOM_CROP_PIXELS,
            screen
        );

    if (height <= top + bottom)
        return;

    /*
     * Vùng thực sự được phép render.
     *
     * Không thay frame.
     * Không thay center.
     * Không đổi safe area.
     */
    CGFloat visibleHeight =
        height - top - bottom;

    CGRect cropRect =
        CGRectMake(
            0.0,
            top,
            width,
            visibleHeight
        );

    CAShapeLayer *mask =
        [CAShapeLayer layer];

    CGPathRef path =
        CGPathCreateWithRect(
            cropRect,
            NULL
        );

    mask.path = path;
    mask.frame = bounds;

    CGPathRelease(path);

    /*
     * Crop thật.
     */
    window.layer.mask = mask;

    window.layer.masksToBounds = YES;
}

#pragma mark - Uniform scaling

static void SC16ApplyScale(UIWindow *window) {

    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (SC16IsSystemOverlayWindow(window))
        return;

    /*
     * Chỉ scale content layer.
     *
     * Không scale window.frame.
     * Không scale UIWindow geometry.
     */
    CGFloat scale =
        SC16UniformScaleForWindow(window);

    /*
     * Center point của layer.
     */
    CALayer *layer =
        window.layer;

    CGPoint center =
        layer.position;

    /*
     * Giữ anchor ở giữa.
     */
    layer.anchorPoint =
        CGPointMake(0.5, 0.5);

    /*
     * Giữ layer tại đúng tâm.
     */
    layer.position =
        center;

    /*
     * Uniform scale X = Y.
     */
    layer.affineTransform =
        CGAffineTransformMakeScale(
            scale,
            scale
        );
}

#pragma mark - Apply window

static void SC16ApplyWindow(UIWindow *window) {

    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (SC16IsSystemOverlayWindow(window))
        return;

    /*
     * Không đụng window geometry.
     *
     * Crop trước.
     * Scale sau.
     */
    SC16ApplyCrop(window);
    SC16ApplyScale(window);
}

#pragma mark - Apply scene

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

        if (!window)
            continue;

        if (window.hidden)
            continue;

        if (window.alpha <= 0.0)
            continue;

        SC16ApplyWindow(window);
    }
}

#pragma mark - All scenes

static void SC16ApplyAllScenes(void) {

    if (!SC16Enabled())
        return;

    if (SC16Updating)
        return;

    SC16Updating = YES;

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

        SC16ApplyScene(windowScene);
    }

    SC16Updating = NO;
}

#pragma mark - Reapply

static void SC16Reapply(void) {

    if (!SC16Enabled())
        return;

    /*
     * Đợi UIKit hoàn tất rotation/layout.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();
        }
    );
}

#pragma mark - UIWindow hook

%hook UIWindow

/*
 * Window xuất hiện.
 */
- (void)makeKeyAndVisible {

    %orig;

    if (!SC16Enabled())
        return;

    SC16Reapply();
}

/*
 * KHÔNG hook setFrame:
 *
 * Nếu hook setFrame rồi sửa frame ở đây sẽ gây:
 *
 * setFrame
 *   ↓
 * setFrame
 *   ↓
 * setFrame
 *   ↓
 * lag / giật / layout loop
 *
 * Bản này tuyệt đối không làm vậy.
 */
- (void)layoutSubviews {

    %orig;

    if (!SC16Enabled())
        return;

    if (SC16Updating)
        return;

    /*
     * UIKit đã cập nhật bounds/orientation.
     *
     * Tính lại crop theo kích thước hiện tại.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!self)
                return;

            SC16ApplyWindow(self);
        }
    );
}

%end

#pragma mark - Constructor

%ctor {

    @autoreleasepool {

        if (!SC16Enabled())
            return;

        /*
         * Initial launch.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ApplyAllScenes();
            }
        );

        NSNotificationCenter *center =
            NSNotificationCenter.defaultCenter;

        /*
         * App active.
         */
        [center addObserverForName:
            UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16Reapply();
            }
        ];

        /*
         * Scene activate.
         */
        [center addObserverForName:
            UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16Reapply();
            }
        ];

        /*
         * Scene connect.
         */
        [center addObserverForName:
            UISceneWillConnectNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16Reapply();
            }
        ];

        /*
         * Rotation.
         *
         * Không ép orientation.
         *
         * UIKit tự xoay.
         * Sau khi bounds mới xuất hiện,
         * chúng ta crop lại đúng 34/34.
         */
        [center addObserverForName:
            UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                /*
                 * 2 lần main-queue tick giúp tránh lấy
                 * bounds cũ trong lúc UIKit đang rotation.
                 */
                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                SC16ApplyAllScenes();
                            }
                        );
                    }
                );
            }
        ];
    }
}
