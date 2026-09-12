#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

/*
 * Góc của card đa nhiệm.
 * Không áp dụng corner này lên nội dung UIWindow.
 */
static CGFloat const SC16_MULTITASK_RADIUS = 2.0;

#pragma mark - State

static BOOL SC16Enabled(void)
{
    NSString *version = UIDevice.currentDevice.systemVersion;

    /*
     * Tweak hiện chỉ dành cho iOS 16.4.
     */
    return [version hasPrefix:@"16.4"];
}

static BOOL SC16IsKeyboardWindow(UIWindow *window)
{
    if (!window)
        return YES;

    NSString *className = NSStringFromClass(window.class);

    if ([className containsString:@"UITextEffectsWindow"])
        return YES;

    if ([className containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([className containsString:@"Keyboard"])
        return YES;

    return NO;
}

static BOOL SC16IsStatusBarWindow(UIWindow *window)
{
    if (!window)
        return YES;

    NSString *className = NSStringFromClass(window.class);

    if ([className containsString:@"StatusBar"])
        return YES;

    if ([className containsString:@"_UIStatusBar"])
        return YES;

    return NO;
}

static BOOL SC16IsSystemWindow(UIWindow *window)
{
    if (!window)
        return YES;

    if (SC16IsKeyboardWindow(window))
        return YES;

    if (SC16IsStatusBarWindow(window))
        return YES;

    /*
     * Không đụng các window thuộc hệ thống.
     *
     * Quan trọng:
     * Control Center / Notification / Lock Screen
     * không được crop theo UIWindow của app.
     */
    NSString *className = NSStringFromClass(window.class);

    if ([className containsString:@"SB"])
        return YES;

    if ([className containsString:@"SpringBoard"])
        return YES;

    if ([className containsString:@"CoverSheet"])
        return YES;

    if ([className containsString:@"Notification"])
        return YES;

    if ([className containsString:@"ControlCenter"])
        return YES;

    return NO;
}

#pragma mark - Window Detection

static UIWindowScene *SC16WindowSceneForWindow(UIWindow *window)
{
    if (!window)
        return nil;

    UIWindowScene *scene = window.windowScene;

    if (scene)
        return scene;

    return nil;
}

static CGRect SC16ScreenBoundsForWindow(UIWindow *window)
{
    UIWindowScene *scene = SC16WindowSceneForWindow(window);

    if (scene)
        return scene.screen.bounds;

    UIScreen *screen = window.screen;

    if (screen)
        return screen.bounds;

    return UIScreen.mainScreen.bounds;
}

#pragma mark - Crop

static void SC16ApplyRealCrop(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (!window)
        return;

    /*
     * Tuyệt đối không crop window hệ thống.
     */
    if (SC16IsSystemWindow(window))
        return;

    if (window.hidden)
        return;

    if (window.alpha <= 0.0)
        return;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return;

    /*
     * Chỉ xử lý các scene đang tồn tại.
     */
    if (scene.activationState == UISceneActivationStateUnattached)
        return;

    CGRect screenBounds = SC16ScreenBoundsForWindow(window);

    CGFloat screenWidth = CGRectGetWidth(screenBounds);
    CGFloat screenHeight = CGRectGetHeight(screenBounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0)
        return;

    /*
     * Lấy bounds hiện tại của WINDOW.
     *
     * Không dùng transform.
     * Không scale.
     * Không đổi aspect ratio.
     */
    CGRect oldBounds = window.bounds;

    CGFloat width = CGRectGetWidth(oldBounds);
    CGFloat height = CGRectGetHeight(oldBounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    /*
     * QUAN TRỌNG CHO ROTATION
     *
     * Crop luôn theo chiều dọc hiện tại của UIWindow.
     *
     * Portrait:
     *     1248 x 2778
     *
     * Landscape:
     *     2778 x 1248
     *
     * Vì vậy không hard-code 1248/2778.
     * UIKit đã xoay bounds của window trước khi chúng ta xử lý.
     */

    CGFloat topCrop = SC16_TOP_CROP;
    CGFloat bottomCrop = SC16_BOTTOM_CROP;

    /*
     * Nếu window đang landscape thì
     * chiều cao hiện tại chính là cạnh 1248.
     *
     * Tuyệt đối không lấy cạnh 2778 để crop.
     */
    if (height <= topCrop + bottomCrop)
        return;

    CGFloat newHeight = height - topCrop - bottomCrop;

    if (newHeight <= 0.0)
        return;

    /*
     * Không dùng transform.
     */
    window.transform = CGAffineTransformIdentity;

    /*
     * Lưu center hiện tại.
     *
     * Việc này rất quan trọng:
     *
     * Không đẩy toàn bộ UIWindow xuống dưới.
     * Không đổi frame.
     * Chỉ thay đổi vùng bounds được hiển thị.
     */
    CGPoint oldCenter = window.center;

    /*
     * REAL CROP
     *
     * Bounds mới ngắn hơn 68pt.
     *
     * Nội dung nằm ngoài vùng bounds sẽ thực sự
     * không còn được UIWindow render/display.
     */
    CGRect newBounds = oldBounds;

    newBounds.origin.y = CGRectGetMinY(oldBounds) + topCrop;
    newBounds.size.height = newHeight;

    /*
     * Không thay đổi width.
     */
    newBounds.size.width = width;

    window.bounds = newBounds;

    /*
     * Giữ tâm cố định.
     *
     * Vì vậy UI không bị đẩy xuống.
     */
    window.center = oldCenter;

    /*
     * Không animate crop.
     */
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    [window setNeedsLayout];

    [CATransaction commit];
}

#pragma mark - Restore / Rotation

static void SC16ResetWindowGeometry(UIWindow *window)
{
    if (!window)
        return;

    if (SC16IsSystemWindow(window))
        return;

    /*
     * Chỉ dùng trong trường hợp UIKit vừa rotation
     * và window đã được UIKit cập nhật lại geometry.
     *
     * Không tự scale.
     */
    window.transform = CGAffineTransformIdentity;
}

static void SC16ApplyWindow(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16Enabled())
        return;

    if (SC16IsSystemWindow(window))
        return;

    SC16ResetWindowGeometry(window);
    SC16ApplyRealCrop(window);
}

#pragma mark - Scene

static void SC16ApplyScene(UIWindowScene *scene)
{
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState == UISceneActivationStateUnattached)
        return;

    /*
     * iOS 15+:
     * UIWindowScene.windows
     *
     * Không dùng UIApplication.windows.
     */
    NSArray<UIWindow *> *windows = scene.windows;

    for (UIWindow *window in windows)
    {
        if (!window)
            continue;

        if (window.hidden)
            continue;

        SC16ApplyWindow(window);
    }
}

static void SC16ApplyAllScenes(void)
{
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    if (!application)
        return;

    NSSet<UIScene *> *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes)
    {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        SC16ApplyScene(windowScene);
    }
}

#pragma mark - Delayed Apply

static void SC16ScheduleApply(void)
{
    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyAllScenes;
    });
}

#pragma mark - UIWindow Hook

%hook UIWindow

- (void)makeKeyAndVisible
{
    %orig;

    if (!SC16Enabled())
        return;

    /*
     * Đợi UIKit hoàn tất quá trình tạo window.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyWindow(self);
    });
}

- (void)setHidden:(BOOL)hidden
{
    %orig(hidden);

    if (!SC16Enabled())
        return;

    if (hidden)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyWindow(self);
    });
}

%end

#pragma mark - UIApplication Lifecycle

%ctor
{
    @autoreleasepool
    {
        if (!SC16Enabled())
            return;

        /*
         * Initial apply.
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
            usingBlock:^(__unused NSNotification *notification)
        {
            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();
                }
            );
        }];

        /*
         * Scene activate.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification)
        {
            UIScene *scene = notification.object;

            if (![scene isKindOfClass:[UIWindowScene class]])
                return;

            /*
             * Đợi một vòng runloop để UIKit hoàn tất
             * scene/window geometry.
             */
            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            );
        }];

        /*
         * Scene foreground.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneWillEnterForegroundNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification)
        {
            UIScene *scene = notification.object;

            if (![scene isKindOfClass:[UIWindowScene class]])
                return;

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            );
        }];

        /*
         * Rotation.
         *
         * Không dùng UIWindowSceneDidUpdateNotification.
         *
         * UIDeviceOrientationDidChangeNotification
         * có trên iOS 16.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification)
        {
            /*
             * UIKit cần thời gian cập nhật orientation,
             * bounds và scene geometry.
             *
             * Chờ 2 runloop tick.
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
        }];
    }
}
