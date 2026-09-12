#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;
static CGFloat const SC16_CORNER_RADIUS = 2.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

static BOOL SC16IsSystemWindow(UIWindow *window) {
    if (!window)
        return YES;

    NSString *name = NSStringFromClass(window.class);

    if ([name containsString:@"UITextEffectsWindow"])
        return YES;

    if ([name containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([name containsString:@"Keyboard"])
        return YES;

    if ([name containsString:@"StatusBar"])
        return YES;

    if ([name containsString:@"_UIStatusBar"])
        return YES;

    return NO;
}

static void SC16ApplyCrop(UIWindow *window) {
    if (!SC16Enabled() || !window)
        return;

    if (SC16IsSystemWindow(window))
        return;

    if (window.hidden || window.alpha <= 0.0)
        return;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGRect screenBounds = screen.bounds;

    CGFloat screenWidth = CGRectGetWidth(screenBounds);
    CGFloat screenHeight = CGRectGetHeight(screenBounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0)
        return;

    CGFloat topCrop = SC16_TOP_CROP;
    CGFloat bottomCrop = SC16_BOTTOM_CROP;

    if (screenHeight <= topCrop + bottomCrop)
        return;

    CGRect bounds = window.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    CGFloat visibleHeight =
        height - topCrop - bottomCrop;

    if (visibleHeight <= 0.0)
        return;

    /*
     * Không scale X/Y khác nhau.
     * Không kéo méo nội dung.
     */
    window.transform = CGAffineTransformIdentity;

    /*
     * Giữ nguyên tâm UIWindow.
     * Chỉ thay đổi vùng bounds để phần trên/dưới
     * nằm ngoài vùng hiển thị.
     */
    CGPoint center = window.center;

    CGRect croppedBounds = bounds;

    croppedBounds.origin.y =
        CGRectGetMinY(bounds) + topCrop;

    croppedBounds.size.height = visibleHeight;

    window.bounds = croppedBounds;
    window.center = center;

    [window setNeedsLayout];
    [window layoutIfNeeded];
}

static void SC16ApplyCorners(UIWindow *window) {
    if (!window)
        return;

    if (SC16IsSystemWindow(window))
        return;

    window.layer.cornerRadius = SC16_CORNER_RADIUS;
    window.layer.masksToBounds = YES;
}

static void SC16ApplyWindow(UIWindow *window) {
    if (!window)
        return;

    SC16ApplyCrop(window);
    SC16ApplyCorners(window);
}

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled() || !scene)
        return;

    /*
     * scene.windows là API đúng trên iOS 15+.
     * Không sử dụng UIApplication.windows.
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
     * Không crop đồng bộ trong setFrame.
     * Tránh vòng lặp layout và giảm lag khi rotation.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.hidden)
            SC16ApplyWindow(self);
    });
}

%end

%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        /*
         * Apply sau khi tweak được load.
         */
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyAllScenes();
        });

        /*
         * App trở lại foreground/active.
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
         * Scene được activate.
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
         * Scene vào foreground.
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
         * Thiết bị xoay.
         *
         * Không dùng UIWindowSceneDidUpdateNotification
         * vì SDK iOS 16.5 không có symbol đó.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                /*
                 * Đợi UIKit hoàn tất quá trình rotation.
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
