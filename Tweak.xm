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

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    UIInterfaceOrientation orientation =
        SC16OrientationForWindow(window);

    /*
     * Dọc:
     *
     * ┌──────────────────────┐
     * │      CROP 34px       │
     * ├──────────────────────┤
     * │                      │
     * │       CONTENT        │
     * │                      │
     * ├──────────────────────┤
     * │      CROP 34px       │
     * └──────────────────────┘
     *
     * Ngang cũng dùng cùng nguyên tắc:
     * crop theo TOP/BOTTOM của vùng hiển thị hiện tại,
     * không xoay ngược hệ tọa độ.
     */

    CGFloat top = SC16_TOP_CROP;
    CGFloat bottom = SC16_BOTTOM_CROP;

    if (orientation == UIInterfaceOrientationLandscapeLeft ||
        orientation == UIInterfaceOrientationLandscapeRight) {

        /*
         * Khi ngang, UIKit đã đổi bounds của UIWindow.
         *
         * Không crop LEFT/RIGHT.
         * Vẫn crop 34px ở hai cạnh trên/dưới
         * theo hệ tọa độ hiện tại của UIWindow.
         */
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
    if (!window || !window.layer)
        return;

    CGRect bounds = window.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGRect cropRect = SC16CropRectForWindow(window);

    /*
     * Dùng mask để CẮT THẬT vùng ngoài crop.
     *
     * Không đổi window.frame.
     * Không đổi window.bounds.
     * Không tạo vùng đen bằng cách resize window.
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
     * Bo góc ngoài của vùng hiển thị.
     */
    window.layer.cornerRadius =
        SC16_CORNER_RADIUS;

    window.layer.masksToBounds = YES;
}

#pragma mark - Content Scaling

static void SC16ApplyContentTransform(UIWindow *window) {
    if (!window || !window.rootViewController)
        return;

    UIView *rootView =
        window.rootViewController.view;

    if (!rootView)
        return;

    CGRect windowBounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(windowBounds);

    CGFloat height =
        CGRectGetHeight(windowBounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGRect cropRect =
        SC16CropRectForWindow(window);

    CGFloat cropWidth =
        CGRectGetWidth(cropRect);

    CGFloat cropHeight =
        CGRectGetHeight(cropRect);

    if (cropWidth <= 0.0 || cropHeight <= 0.0)
        return;

    /*
     * QUAN TRỌNG:
     *
     * Không scale X/Y riêng.
     *
     * Dùng cùng một scale cho cả X và Y
     * để hình không bị méo.
     */

    CGFloat contentWidth =
        CGRectGetWidth(rootView.bounds);

    CGFloat contentHeight =
        CGRectGetHeight(rootView.bounds);

    if (contentWidth <= 0.0 || contentHeight <= 0.0)
        return;

    CGFloat scaleX =
        cropWidth / contentWidth;

    CGFloat scaleY =
        cropHeight / contentHeight;

    /*
     * Scale đồng đều.
     *
     * Chọn MIN để luôn giữ nguyên aspect ratio.
     */
    CGFloat scale =
        MIN(scaleX, scaleY);

    /*
     * Không để scale quá nhỏ do một layout bất thường.
     */
    if (!isfinite(scale) || scale <= 0.0)
        return;

    /*
     * Reset transform trước.
     */
    rootView.transform =
        CGAffineTransformIdentity;

    /*
     * Sau khi scale, tính kích thước thực.
     */
    CGFloat scaledWidth =
        contentWidth * scale;

    CGFloat scaledHeight =
        contentHeight * scale;

    /*
     * Căn GIỮA trong vùng crop.
     */
    CGFloat x =
        CGRectGetMinX(cropRect) +
        (cropWidth - scaledWidth) / 2.0;

    CGFloat y =
        CGRectGetMinY(cropRect) +
        (cropHeight - scaledHeight) / 2.0;

    /*
     * Không đổi frame của UIWindow.
     *
     * Chỉ transform root view.
     */
    rootView.transform =
        CGAffineTransformMakeScale(
            scale,
            scale
        );

    rootView.center =
        CGPointMake(
            x + scaledWidth / 2.0,
            y + scaledHeight / 2.0
        );
}

#pragma mark - Apply

static void SC16ApplyToWindow(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (window.hidden)
        return;

    if (window.alpha <= 0.0)
        return;

    /*
     * Tránh re-entry.
     */
    if (SC16Applying)
        return;

    SC16Applying = YES;

    /*
     * Không resize UIWindow.
     * Chỉ:
     *
     * 1. Mask -> crop thật
     * 2. Root VC -> scale đồng đều + center
     */
    SC16ApplyMask(window);

    SC16ApplyContentTransform(window);

    SC16Applying = NO;
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

    for (UIWindow *window in scene.windows) {

        /*
         * Không đụng vào keyboard / system overlay
         * / alert window không thuộc app.
         */
        if (!window.hidden &&
            window.windowLevel == UIWindowLevelNormal) {

            SC16ApplyToWindow(window);
        }
    }
}

#pragma mark - All Scenes

static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    if (@available(iOS 13.0, *)) {

        UIApplication *app =
            UIApplication.sharedApplication;

        for (UIScene *scene in app.connectedScenes) {

            if (![scene
                  isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            SC16ApplyScene(windowScene);
        }

    } else {

        /*
         * iOS 16.4 không chạy nhánh này,
         * giữ lại để source an toàn.
         */
        UIApplication *app =
            UIApplication.sharedApplication;

        for (UIWindow *window in app.windows) {
            SC16ApplyToWindow(window);
        }
    }
}

#pragma mark - Delayed Apply

static void SC16ScheduleApply(void) {

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*
             * Đợi UIKit hoàn thành layout/orientation
             * rồi mới apply.
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

- (void)makeKeyAndVisible {

    %orig;

    if (!SC16Enabled())
        return;

    /*
     * Không sửa frame tại đây.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyToWindow(self);
        }
    );
}

- (void)layoutSubviews {

    %orig;

    if (!SC16Enabled())
        return;

    /*
     * UIKit đã layout xong.
     * Chỉ apply mask/scale.
     *
     * Không hook setFrame:
     * => tránh vòng lặp + giật/lag.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyToWindow(self);
        }
    );
}

%end

#pragma mark - UIApplication

%hook UIApplication

- (void)setStatusBarOrientation:(UIInterfaceOrientation)orientation {

    %orig;

    if (!SC16Enabled())
        return;

    SC16ScheduleApply();
}

%end

#pragma mark - View Controller Rotation

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {

    %orig;

    if (!SC16Enabled())
        return;

    SC16ScheduleApply();
}

- (void)viewDidLayoutSubviews {

    %orig;

    if (!SC16Enabled())
        return;

    /*
     * Không chỉnh frame ở đây.
     * Chỉ re-apply sau khi UIKit layout.
     */
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

        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];

        /*
         * App active.
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
         * Scene active.
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
                         isKindOfClass:[UIWindowScene class]]) {

                        SC16ApplyScene(
                            (UIWindowScene *)scene
                        );
                    }
                }
            ];

            /*
             * Orientation / bounds thay đổi.
             *
             * Không dùng
             * UIWindowSceneDidUpdateNotification
             * vì SDK của bạn không có symbol đó.
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
        }

        /*
         * Screen parameters thay đổi.
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
