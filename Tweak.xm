#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Configuration

static const CGFloat SC16_CROP = 34.0;
static const CGFloat SC16_MULTITASK_RADIUS = 2.0;

#pragma mark - Runtime

static BOOL SC16IsIOS16(void) {
    NSOperatingSystemVersion v =
        UIDevice.currentDevice.systemVersion.length
        ? NSProcessInfo.processInfo.operatingSystemVersion
        : (NSOperatingSystemVersion){0, 0, 0};

    return v.majorVersion == 16;
}

/*
 * Không crop các UIWindow thuộc UIKit/System UI.
 *
 * Điều này đặc biệt quan trọng đối với:
 *
 * - Status Bar
 * - Keyboard
 * - Control Centre
 * - Notification
 */
static BOOL SC16ExcludedWindow(UIWindow *window) {
    if (!window)
        return YES;

    NSString *cls = NSStringFromClass(window.class);

    static NSArray<NSString *> *excludedClasses;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        excludedClasses = @[
            @"UITextEffectsWindow",
            @"UIRemoteKeyboardWindow",
            @"_UIRemoteKeyboardWindow",
            @"UIStatusBarWindow",
            @"_UIStatusBarWindow",
            @"StatusBar",
            @"Keyboard",
            @"TextEffects",
            @"Notification",
            @"ControlCenter",
            @"SBControlCenter",
            @"SBNotification"
        ];
    });

    for (NSString *name in excludedClasses) {
        if ([cls rangeOfString:name
                       options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }

    return NO;
}

static BOOL SC16IsUsableWindow(UIWindow *window) {
    if (!window)
        return NO;

    if (window.hidden)
        return NO;

    if (window.alpha <= 0.0)
        return NO;

    if (SC16ExcludedWindow(window))
        return NO;

    return YES;
}

#pragma mark - Geometry

/*
 * Lấy vùng crop theo orientation của chính UIWindowScene.
 *
 * Portrait:
 *
 *     width  = 1284
 *     height = 2778
 *
 *     crop:
 *       top    34
 *       bottom 34
 *
 * Landscape:
 *
 *     width  = 2778
 *     height = 1284
 *
 *     crop:
 *       left  34
 *       right 34
 *
 * Như vậy KHÔNG bao giờ nhầm chiều 1248
 * với chiều 2778.
 */
static CGRect SC16CropRectForWindow(UIWindow *window) {
    CGRect bounds = window.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return CGRectZero;

    BOOL landscape = width > height;

    if (!landscape) {
        CGFloat newHeight =
            height - (SC16_CROP * 2.0);

        if (newHeight <= 0.0)
            return CGRectZero;

        return CGRectMake(
            CGRectGetMinX(bounds),
            CGRectGetMinY(bounds) + SC16_CROP,
            width,
            newHeight
        );
    }

    CGFloat newWidth =
        width - (SC16_CROP * 2.0);

    if (newWidth <= 0.0)
        return CGRectZero;

    return CGRectMake(
        CGRectGetMinX(bounds) + SC16_CROP,
        CGRectGetMinY(bounds),
        newWidth,
        height
    );
}

#pragma mark - Viewport

/*
 * Không thay đổi UIWindow.
 *
 * Thay vào đó, crop view hierarchy ở root view.
 *
 * UIWindow vẫn giữ nguyên kích thước native,
 * nên UIKit không scale toàn màn hình.
 *
 * Nội dung root view được đặt trong viewport
 * mới và phần ngoài viewport không tồn tại
 * trong hierarchy hiển thị.
 */

static const void *SC16OriginalFrameKey =
    &SC16OriginalFrameKey;

static const void *SC16ViewportKey =
    &SC16ViewportKey;

static void SC16ApplyRootViewport(UIWindow *window) {
    if (!SC16IsIOS16())
        return;

    if (!SC16IsUsableWindow(window))
        return;

    UIView *rootView =
        window.rootViewController.view;

    if (!rootView)
        return;

    CGRect windowBounds =
        window.bounds;

    CGRect cropRect =
        SC16CropRectForWindow(window);

    if (CGRectIsEmpty(cropRect))
        return;

    /*
     * Chỉ áp dụng cho root view chiếm toàn UIWindow.
     *
     * Không can thiệp những view overlay nhỏ
     * như alert / keyboard / system presentation.
     */
    if (rootView.superview != window)
        return;

    /*
     * Lưu frame gốc một lần.
     */
    NSValue *savedValue =
        objc_getAssociatedObject(
            rootView,
            SC16OriginalFrameKey
        );

    if (!savedValue) {
        objc_setAssociatedObject(
            rootView,
            SC16OriginalFrameKey,
            [NSValue valueWithCGRect:rootView.frame],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    /*
     * Crop theo orientation.
     *
     * Không transform.
     * Không scale.
     */
    CGRect viewport = cropRect;

    rootView.frame = viewport;

    /*
     * Center giữ nguyên giữa màn hình.
     */
    rootView.center =
        CGPointMake(
            CGRectGetMidX(windowBounds),
            CGRectGetMidY(windowBounds)
        );

    /*
     * Clip root content đúng viewport.
     */
    rootView.layer.masksToBounds = YES;

    objc_setAssociatedObject(
        window,
        SC16ViewportKey,
        rootView,
        OBJC_ASSOCIATION_ASSIGN
    );

    [rootView setNeedsLayout];
}

#pragma mark - Window Apply

static void SC16ApplyWindow(UIWindow *window) {
    if (!SC16IsIOS16())
        return;

    if (!SC16IsUsableWindow(window))
        return;

    SC16ApplyRootViewport(window);
}

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16IsIOS16())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached) {
        return;
    }

    /*
     * iOS 15+:
     *
     * UIWindowScene.windows
     *
     * Không sử dụng UIApplication.windows.
     */
    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows) {
        SC16ApplyWindow(window);
    }
}

static void SC16ApplyAllScenes(void) {
    if (!SC16IsIOS16())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    for (UIScene *scene in
         application.connectedScenes) {

        if (![scene
            isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        SC16ApplyScene(
            (UIWindowScene *)scene
        );
    }
}

#pragma mark - Safe Reapply

static void SC16ReapplyAsync(UIWindow *window) {
    if (!window)
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!SC16IsIOS16())
                return;

            if (!SC16IsUsableWindow(window))
                return;

            SC16ApplyWindow(window);
        }
    );
}

#pragma mark - UIWindow Hooks

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16IsIOS16())
        return;

    SC16ReapplyAsync(self);
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    if (!SC16IsIOS16())
        return;

    if (hidden)
        return;

    SC16ReapplyAsync(self);
}

- (void)setRootViewController:
    (UIViewController *)rootViewController {

    %orig(rootViewController);

    if (!SC16IsIOS16())
        return;

    SC16ReapplyAsync(self);
}

- (void)didMoveToWindow {
    %orig;

    if (!SC16IsIOS16())
        return;

    SC16ReapplyAsync(self);
}

%end

#pragma mark - UIView Rotation / Layout

/*
 * Root view có thể bị UIKit layout lại sau rotation.
 *
 * Hook layoutSubviews nhưng chỉ xử lý root view
 * đã được đánh dấu bởi SC16ApplyRootViewport().
 *
 * Không dùng timer.
 * Không gọi layoutIfNeeded().
 * Không sửa UIWindow.
 */

%hook UIView

- (void)layoutSubviews {
    %orig;

    if (!SC16IsIOS16())
        return;

    UIWindow *window = self.window;

    if (!window)
        return;

    if (!SC16IsUsableWindow(window))
        return;

    UIView *root =
        window.rootViewController.view;

    if (!root || self != root)
        return;

    CGRect cropRect =
        SC16CropRectForWindow(window);

    if (CGRectIsEmpty(cropRect))
        return;

    CGRect windowBounds =
        window.bounds;

    CGRect expectedFrame =
        cropRect;

    expectedFrame.origin =
        CGPointMake(
            CGRectGetMinX(windowBounds),
            CGRectGetMinY(windowBounds)
        );

    /*
     * Không để Auto Layout / rotation
     * trả root view về full screen.
     */
    if (!CGRectEqualToRect(
            self.frame,
            cropRect)) {

        self.frame = cropRect;

        self.center =
            CGPointMake(
                CGRectGetMidX(windowBounds),
                CGRectGetMidY(windowBounds)
            );
    }

    self.layer.masksToBounds = YES;
}

%end

#pragma mark - SpringBoard App Switcher

/*
 * Phần này CHỈ có ý nghĩa khi tweak được inject
 * vào SpringBoard.
 *
 * Không hook toàn bộ UIView để tránh lag/safe mode.
 *
 * SBAppSwitcherPageView là view đại diện cho
 * app card trong Fluid App Switcher trên iOS 16.
 */

@interface SBAppSwitcherPageView : UIView

@property(nonatomic, assign)
CGFloat cornerRadius;

@end

%group SpringBoardSwitcher

%hook SBAppSwitcherPageView

- (void)setCornerRadius:(CGFloat)radius {
    /*
     * Ép card về góc gần vuông.
     *
     * 2.0 = vẫn hơi bo, nhưng gần như vuông.
     */
    %orig(SC16_MULTITASK_RADIUS);
}

- (void)layoutSubviews {
    %orig;

    /*
     * Sau khi SpringBoard tự layout xong,
     * áp dụng lại radius.
     */
    self.layer.cornerRadius =
        SC16_MULTITASK_RADIUS;

    self.layer.masksToBounds = YES;
}

%end

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {

        if (!SC16IsIOS16())
            return;

        /*
         * Detect SpringBoard mà không cần private header.
         */
        NSString *processName =
            NSProcessInfo.processInfo.processName;

        if ([processName isEqualToString:@"SpringBoard"]) {

            %init(SpringBoardSwitcher);

            /*
             * Không chạy crop UIWindow trong SpringBoard.
             *
             * Tránh phá:
             * - Status Bar
             * - Control Centre
             * - Notification
             * - Lock Screen
             */
            return;
        }

        /*
         * App process.
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
        [center
            addObserverForName:
                UIApplicationDidBecomeActiveNotification
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:
            ^(__unused NSNotification *notification) {

                SC16ApplyAllScenes();
            }];

        /*
         * Scene active.
         */
        [center
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:
            ^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if (![scene
                    isKindOfClass:[UIWindowScene class]]) {
                    return;
                }

                SC16ApplyScene(
                    (UIWindowScene *)scene
                );
            }];

        /*
         * Scene foreground.
         */
        [center
            addObserverForName:
                UISceneWillEnterForegroundNotification
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:
            ^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if (![scene
                    isKindOfClass:[UIWindowScene class]]) {
                    return;
                }

                SC16ApplyScene(
                    (UIWindowScene *)scene
                );
            }];

        /*
         * Rotation.
         *
         * Chờ UIKit hoàn thành rotation rồi
         * mới tính lại cropRect.
         */
        [center
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:NSOperationQueue.mainQueue
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
