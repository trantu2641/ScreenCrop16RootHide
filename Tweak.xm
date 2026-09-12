#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;
static CGFloat const SC16_CORNER_RADIUS = 2.0;

#pragma mark - State

static NSMutableDictionary *SC16OriginalFrames;
static NSMutableDictionary *SC16OriginalBounds;
static NSMutableDictionary *SC16OriginalTransforms;

#pragma mark - Enable

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

#pragma mark - Window filtering

static BOOL SC16IsSystemWindow(UIWindow *window) {
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

    return NO;
}

#pragma mark - Screen

static CGRect SC16ScreenBounds(UIWindow *window) {
    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    return screen.bounds;
}

#pragma mark - Crop

static void SC16ApplyCrop(UIWindow *window) {
    if (!SC16Enabled() || !window)
        return;

    if (SC16IsSystemWindow(window))
        return;

    if (window.hidden)
        return;

    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    CGRect screenBounds = screen.bounds;

    CGFloat screenWidth = CGRectGetWidth(screenBounds);
    CGFloat screenHeight = CGRectGetHeight(screenBounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0)
        return;

    CGFloat topCrop = SC16_TOP_CROP;
    CGFloat bottomCrop = SC16_BOTTOM_CROP;

    if (screenHeight <= topCrop + bottomCrop)
        return;

    /*
     * Không dùng UIWindow.frame để đẩy nội dung xuống.
     *
     * Crop trực tiếp vùng hiển thị của UIWindow.
     */
    CGRect bounds = window.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGFloat visibleHeight = height - topCrop - bottomCrop;

    if (visibleHeight <= 0.0)
        return;

    /*
     * Giữ tỷ lệ 1:1.
     * Không scale riêng X/Y => không méo hình.
     */
    CGFloat scaleX = width / width;
    CGFloat scaleY = visibleHeight / visibleHeight;

    if (scaleX <= 0.0 || scaleY <= 0.0)
        return;

    /*
     * Chỉ thay đổi bounds để loại bỏ 34px trên và 34px dưới.
     */
    CGRect croppedBounds = bounds;

    croppedBounds.origin.y =
        CGRectGetMinY(bounds) + topCrop;

    croppedBounds.size.height = visibleHeight;

    CGPoint center = window.center;

    window.transform = CGAffineTransformIdentity;

    window.bounds = croppedBounds;
    window.center = center;

    [window setNeedsLayout];
    [window layoutIfNeeded];
}

#pragma mark - Corners

static void SC16ApplyCorners(UIWindow *window) {
    if (!window)
        return;

    if (SC16IsSystemWindow(window))
        return;

    /*
     * Góc gần vuông, chỉ bo 2px.
     */
    window.layer.cornerRadius = SC16_CORNER_RADIUS;
    window.layer.masksToBounds = YES;
}

#pragma mark - Window

static void SC16ApplyWindow(UIWindow *window) {
    if (!window)
        return;

    SC16ApplyCrop(window);
    SC16ApplyCorners(window);
}

#pragma mark - Scene

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled() || !scene)
        return;

    /*
     * Dùng scene.windows thay cho UIApplication.windows.
     * Không bị warning deprecated trên iOS 16 SDK.
     */
    NSArray<UIWindow *> *windows = scene.windows;

    for (UIWindow *window in windows) {
        if (!window.hidden)
            SC16ApplyWindow(window);
    }
}

static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    for (UIScene *scene in application.connectedScenes) {

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

#pragma mark - UIWindow Hook

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyWindow(self);
    });
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    if (!SC16Enabled() || hidden)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyWindow(self);
    });
}

- (void)setFrame:(CGRect)frame {
    %orig(frame);

    if (!SC16Enabled())
        return;

    /*
     * Không xử lý đồng bộ trong setFrame.
     * Tránh vòng lặp layout và giảm giật khi xoay màn hình.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.hidden)
            SC16ApplyWindow(self);
    });
}

%end

#pragma mark - Scene lifecycle

%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        SC16OriginalFrames =
            [NSMutableDictionary dictionary];

        SC16OriginalBounds =
            [NSMutableDictionary dictionary];

        SC16OriginalTransforms =
            [NSMutableDictionary dictionary];

        /*
         * Apply ban đầu.
         */
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyAllScenes();
        });

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
         * Scene activate.
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
         * Scene foreground.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneWillEnterForegroundNotification
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
         * Orientation thay đổi.
         *
         * Không dùng UIWindowSceneDidUpdateNotification
         * vì symbol đó không có trong SDK hiện tại.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                /*
                 * Đợi UIKit hoàn thành rotation rồi apply lại.
                 */
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
