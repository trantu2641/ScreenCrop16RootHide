#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Settings

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static CGFloat const SC16_CORNER_RADIUS = 2.0;
static CGFloat const SC16_MULTITASK_RADIUS = 2.0;

#pragma mark - State

static BOOL SC16Applying = NO;

#pragma mark - iOS 16.4

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

#pragma mark - Orientation

static UIInterfaceOrientation SC16OrientationForWindow(UIWindow *window) {

    if (@available(iOS 13.0, *)) {

        UIWindowScene *scene = window.windowScene;

        if (scene) {

            UIInterfaceOrientation orientation =
                scene.interfaceOrientation;

            if (orientation != UIInterfaceOrientationUnknown) {
                return orientation;
            }
        }
    }

    return UIInterfaceOrientationPortrait;
}

#pragma mark - Crop Rect

static CGRect SC16CropRectForWindow(UIWindow *window) {

    CGRect bounds = window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0) {
        return bounds;
    }

    UIInterfaceOrientation orientation =
        SC16OrientationForWindow(window);

    /*
     * Luôn crop theo cạnh trên / dưới
     * của UIWindow hiện tại.
     *
     * Portrait:
     *
     *   34px CROP
     *   ─────────────
     *   CONTENT
     *   ─────────────
     *   34px CROP
     *
     * Landscape:
     *
     *   34px CROP
     *   ─────────────
     *   CONTENT
     *   ─────────────
     *   34px CROP
     *
     * Không crop trái/phải.
     */

    CGFloat top =
        SC16_TOP_CROP;

    CGFloat bottom =
        SC16_BOTTOM_CROP;

    if (orientation == UIInterfaceOrientationLandscapeLeft ||
        orientation == UIInterfaceOrientationLandscapeRight) {

        top = SC16_TOP_CROP;
        bottom = SC16_BOTTOM_CROP;
    }

    if (height <= top + bottom) {
        return bounds;
    }

    return CGRectMake(
        0.0,
        top,
        width,
        height - top - bottom
    );
}

#pragma mark - Mask

static void SC16ApplyMask(UIWindow *window) {

    if (!window || !window.layer) {
        return;
    }

    CGRect bounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0) {
        return;
    }

    CGRect cropRect =
        SC16CropRectForWindow(window);

    /*
     * Mask là phần QUAN TRỌNG nhất:
     *
     * UIWindow vẫn giữ nguyên frame/bounds.
     * Chỉ hiển thị vùng cropRect.
     *
     * Không dùng:
     *
     * window.frame = ...
     *
     * window.bounds = ...
     *
     * nên tránh việc UIKit đẩy layout.
     */

    CAShapeLayer *mask =
        [CAShapeLayer layer];

    CGPathRef path =
        CGPathCreateWithRoundedRect(
            cropRect,
            SC16_CORNER_RADIUS,
            SC16_CORNER_RADIUS,
            NULL
        );

    mask.path = path;
    mask.frame = bounds;

    CGPathRelease(path);

    window.layer.mask = mask;

    /*
     * Bo góc vùng hiển thị.
     */
    window.layer.cornerRadius =
        SC16_CORNER_RADIUS;

    window.layer.masksToBounds =
        YES;
}

#pragma mark - Content Scaling

static void SC16ApplyContentTransform(UIWindow *window) {

    if (!window) {
        return;
    }

    UIViewController *rootVC =
        window.rootViewController;

    if (!rootVC) {
        return;
    }

    UIView *rootView =
        rootVC.view;

    if (!rootView) {
        return;
    }

    CGRect windowBounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(windowBounds);

    CGFloat height =
        CGRectGetHeight(windowBounds);

    if (width <= 0.0 || height <= 0.0) {
        return;
    }

    CGRect cropRect =
        SC16CropRectForWindow(window);

    CGFloat cropWidth =
        CGRectGetWidth(cropRect);

    CGFloat cropHeight =
        CGRectGetHeight(cropRect);

    if (cropWidth <= 0.0 || cropHeight <= 0.0) {
        return;
    }

    CGRect contentBounds =
        rootView.bounds;

    CGFloat contentWidth =
        CGRectGetWidth(contentBounds);

    CGFloat contentHeight =
        CGRectGetHeight(contentBounds);

    if (contentWidth <= 0.0 ||
        contentHeight <= 0.0) {

        return;
    }

    /*
     * Scale X/Y riêng sẽ làm méo hình.
     *
     * Vì vậy tính một scale duy nhất.
     */
    CGFloat scaleX =
        cropWidth / contentWidth;

    CGFloat scaleY =
        cropHeight / contentHeight;

    CGFloat scale =
        MIN(scaleX, scaleY);

    if (!isfinite(scale) ||
        scale <= 0.0) {

        return;
    }

    /*
     * Reset transform trước khi tính.
     */
    rootView.transform =
        CGAffineTransformIdentity;

    CGFloat scaledWidth =
        contentWidth * scale;

    CGFloat scaledHeight =
        contentHeight * scale;

    /*
     * Căn giữa chính xác trong vùng crop.
     */
    CGFloat centerX =
        CGRectGetMidX(cropRect);

    CGFloat centerY =
        CGRectGetMidY(cropRect);

    rootView.transform =
        CGAffineTransformMakeScale(
            scale,
            scale
        );

    rootView.center =
        CGPointMake(
            centerX,
            centerY
        );
}

#pragma mark - Apply Window

static void SC16ApplyToWindow(UIWindow *window) {

    if (!SC16Enabled()) {
        return;
    }

    if (!window) {
        return;
    }

    if (window.hidden) {
        return;
    }

    if (window.alpha <= 0.0) {
        return;
    }

    /*
     * Chỉ xử lý app window.
     *
     * Không can thiệp vào:
     * Control Center
     * Notification Center
     * system overlay
     */
    if (window.windowLevel != UIWindowLevelNormal) {
        return;
    }

    if (SC16Applying) {
        return;
    }

    SC16Applying = YES;

    /*
     * 1. Cắt thật vùng trên/dưới.
     */
    SC16ApplyMask(window);

    /*
     * 2. Scale đồng đều.
     */
    SC16ApplyContentTransform(window);

    SC16Applying = NO;
}

#pragma mark - Scene

static void SC16ApplyScene(UIWindowScene *scene) {

    if (!SC16Enabled()) {
        return;
    }

    if (!scene) {
        return;
    }

    if (scene.activationState ==
        UISceneActivationStateUnattached) {

        return;
    }

    /*
     * Dùng UIWindowScene.windows.
     *
     * KHÔNG dùng UIApplication.windows.
     */
    for (UIWindow *window in scene.windows) {

        if (!window.hidden &&
            window.windowLevel == UIWindowLevelNormal) {

            SC16ApplyToWindow(window);
        }
    }
}

#pragma mark - All Scenes

static void SC16ApplyAllScenes(void) {

    if (!SC16Enabled()) {
        return;
    }

    if (@available(iOS 13.0, *)) {

        UIApplication *app =
            UIApplication.sharedApplication;

        /*
         * Lấy scene từ connectedScenes.
         */
        for (UIScene *scene in app.connectedScenes) {

            if (![scene
                  isKindOfClass:[UIWindowScene class]]) {

                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            SC16ApplyScene(windowScene);
        }
    }
}

#pragma mark - Delayed Apply

static void SC16ScheduleApply(void) {

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*
             * Cho UIKit hoàn thành orientation/layout
             * trước khi apply lại crop.
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

#pragma mark - UIWindow Hook

%hook UIWindow

- (void)makeKeyAndVisible {

    %orig;

    if (!SC16Enabled()) {
        return;
    }

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SC16ApplyToWindow(self);
        }
    );
}

/*
 * KHÔNG hook setFrame:
 *
 * - tránh vòng lặp layout
 * - tránh giật/lag
 * - tránh đẩy UI
 * - tránh black screen
 *
 * layoutSubviews chỉ re-apply mask sau khi UIKit layout.
 */
- (void)layoutSubviews {

    %orig;

    if (!SC16Enabled()) {
        return;
    }

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SC16ApplyToWindow(self);
        }
    );
}

%end

#pragma mark - View Controller

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {

    %orig;

    if (!SC16Enabled()) {
        return;
    }

    SC16ScheduleApply();
}

- (void)viewDidLayoutSubviews {

    %orig;

    if (!SC16Enabled()) {
        return;
    }

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            UIWindow *window =
                self.view.window;

            if (window) {
                SC16ApplyToWindow(window);
            }
        }
    );
}

%end

#pragma mark - Notifications

%ctor {

    @autoreleasepool {

        if (!SC16Enabled()) {
            return;
        }

        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];

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
         * App trở lại foreground.
         */
        [center addObserverForName:
            UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ScheduleApply();
            }
        ];

        /*
         * Scene activate.
         */
        if (@available(iOS 13.0, *)) {

            [center addObserverForName:
                UISceneDidActivateNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {

                    UIScene *scene =
                        notification.object;

                    if ([scene
                         isKindOfClass:
                         [UIWindowScene class]]) {

                        SC16ApplyScene(
                            (UIWindowScene *)scene
                        );
                    }
                }
            ];
        }

        /*
         * Window trở thành key.
         */
        [center addObserverForName:
            UIWindowDidBecomeKeyNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIWindow *window =
                    notification.object;

                if (window) {
                    SC16ApplyToWindow(window);
                }
            }
        ];

        /*
         * Xoay thiết bị.
         *
         * UIKit sẽ cập nhật UIWindowScene trước,
         * sau đó tweak đọc bounds/orientation mới
         * và áp dụng lại crop.
         */
        [center addObserverForName:
            UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ScheduleApply();
            }
        ];
    }
}
