#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Configuration

static const CGFloat SC16_CROP = 34.0;
static const CGFloat SC16_MULTITASK_RADIUS = 2.0;

#pragma mark - Runtime

static BOOL SC16IsIOS16(void) {
    NSOperatingSystemVersion version =
        NSProcessInfo.processInfo.operatingSystemVersion;

    return version.majorVersion == 16;
}

static BOOL SC16ExcludedWindow(UIWindow *window) {
    if (!window)
        return YES;

    NSString *className =
        NSStringFromClass(window.class);

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
        if ([className rangeOfString:name
                             options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }

    return NO;
}

static BOOL SC16UsableWindow(UIWindow *window) {
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

#pragma mark - Crop Geometry

/*
 * Crop 34px ở hai đầu theo chiều DÀI của nội dung.
 *
 * Portrait:
 *
 *     1284 x 2778
 *
 *     trên  = 34
 *     dưới  = 34
 *
 * Landscape:
 *
 *     2778 x 1284
 *
 *     trái  = 34
 *     phải  = 34
 *
 * Không scale.
 * Không transform.
 * Không làm thay đổi aspect ratio.
 */
static CGRect SC16CropRect(UIWindow *window) {
    CGRect bounds = window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return CGRectZero;

    BOOL landscape =
        width > height;

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

#pragma mark - Root View Crop

static const void *SC16AppliedKey =
    &SC16AppliedKey;

static void SC16ApplyRootView(UIWindow *window) {
    if (!SC16IsIOS16())
        return;

    if (!SC16UsableWindow(window))
        return;

    UIViewController *rootViewController =
        window.rootViewController;

    if (!rootViewController)
        return;

    UIView *rootView =
        rootViewController.view;

    if (!rootView)
        return;

    if (rootView.superview != window)
        return;

    CGRect cropRect =
        SC16CropRect(window);

    if (CGRectIsEmpty(cropRect))
        return;

    CGRect windowBounds =
        window.bounds;

    /*
     * Đánh dấu root view đã được xử lý.
     */
    objc_setAssociatedObject(
        rootView,
        SC16AppliedKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    /*
     * QUAN TRỌNG:
     *
     * Không thay đổi:
     *     window.bounds
     *     window.frame
     *     window.transform
     *
     * Chỉ thay đổi viewport của root view.
     */
    rootView.frame = cropRect;

    rootView.center =
        CGPointMake(
            CGRectGetMidX(windowBounds),
            CGRectGetMidY(windowBounds)
        );

    /*
     * Phần ngoài viewport bị clip thật
     * thay vì phủ bằng một view đen.
     */
    rootView.clipsToBounds = YES;
    rootView.layer.masksToBounds = YES;

    [rootView setNeedsLayout];
}

#pragma mark - Window

static void SC16ApplyWindow(UIWindow *window) {
    if (!SC16IsIOS16())
        return;

    if (!SC16UsableWindow(window))
        return;

    SC16ApplyRootView(window);
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
     * Dùng UIWindowScene.windows.
     * Không dùng UIApplication.windows.
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

    for (UIScene *scene in application.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        SC16ApplyScene(windowScene);
    }
}

static void SC16ScheduleReapply(UIWindow *window) {
    if (!window)
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!SC16IsIOS16())
                return;

            if (!SC16UsableWindow(window))
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

    SC16ScheduleReapply(self);
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    if (!SC16IsIOS16())
        return;

    if (hidden)
        return;

    SC16ScheduleReapply(self);
}

- (void)setRootViewController:(UIViewController *)rootViewController {
    %orig(rootViewController);

    if (!SC16IsIOS16())
        return;

    SC16ScheduleReapply(self);
}

- (void)didMoveToWindow {
    %orig;

    if (!SC16IsIOS16())
        return;

    SC16ScheduleReapply(self);
}

%end

#pragma mark - Root View Layout

%hook UIView

- (void)layoutSubviews {
    %orig;

    if (!SC16IsIOS16())
        return;

    UIWindow *window =
        self.window;

    if (!window)
        return;

    if (!SC16UsableWindow(window))
        return;

    UIViewController *rootViewController =
        window.rootViewController;

    if (!rootViewController)
        return;

    UIView *rootView =
        rootViewController.view;

    if (!rootView)
        return;

    if (self != rootView)
        return;

    /*
     * Chỉ xử lý root view đã được crop.
     */
    NSNumber *applied =
        objc_getAssociatedObject(
            rootView,
            SC16AppliedKey
        );

    if (![applied boolValue])
        return;

    CGRect cropRect =
        SC16CropRect(window);

    if (CGRectIsEmpty(cropRect))
        return;

    CGRect windowBounds =
        window.bounds;

    /*
     * UIKit có thể reset frame khi rotation/layout.
     * Đưa root view trở lại viewport crop.
     *
     * Không scale.
     * Không transform.
     */
    if (!CGRectEqualToRect(
            rootView.frame,
            cropRect)) {

        rootView.frame =
            cropRect;

        rootView.center =
            CGPointMake(
                CGRectGetMidX(windowBounds),
                CGRectGetMidY(windowBounds)
            );
    }

    rootView.clipsToBounds = YES;
    rootView.layer.masksToBounds = YES;
}

%end

#pragma mark - SpringBoard App Switcher

@interface SBAppSwitcherPageView : UIView

@property(nonatomic, assign)
CGFloat cornerRadius;

@end

%group SpringBoardSwitcher

%hook SBAppSwitcherPageView

- (void)setCornerRadius:(CGFloat)radius {
    %orig(SC16_MULTITASK_RADIUS);
}

- (void)layoutSubviews {
    %orig;

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

        NSString *processName =
            NSProcessInfo.processInfo.processName;

        /*
         * SpringBoard:
         *
         * Chỉ xử lý App Switcher.
         *
         * Không crop UIWindow của SpringBoard,
         * tránh phá:
         *
         * - Status Bar
         * - Control Centre
         * - Notification
         * - Lock Screen
         */
        if ([processName isEqualToString:@"SpringBoard"]) {

            %init(SpringBoardSwitcher);

            return;
        }

        /*
         * QUAN TRỌNG:
         *
         * Khởi tạo toàn bộ hook không nằm trong
         * %group.
         *
         * Đây là phần sửa lỗi:
         *
         * non-initialized hook group: _ungrouped
         */
        %init;

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
         * Không dùng UIWindowSceneDidUpdateNotification
         * vì SDK iOS 16.5 không có symbol này.
         */
        [center
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:
            ^(__unused NSNotification *notification) {

                /*
                 * Chờ UIKit hoàn thành rotation.
                 */
                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAllScenes();

                        /*
                         * Một lần nữa ở frame kế tiếp,
                         * phòng trường hợp UIKit vừa layout
                         * lại root view.
                         */
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
