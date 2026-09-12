#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;
static CGFloat const SC16_SCREEN_CORNER_RADIUS = 2.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

/*
 * Chỉ xử lý UIWindow thuộc application.
 * Không đụng vào window của Control Centre,
 * Notification Center hoặc các scene hệ thống.
 */
static BOOL SC16IsApplicationWindow(UIWindow *window) {
    if (!window)
        return NO;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return NO;

    UISceneSession *session = scene.session;

    if (!session)
        return NO;

    return [session.role isEqualToString:
            UIWindowSceneSessionRoleApplication];
}

/*
 * Crop thật bằng bounds.
 *
 * Không thay đổi frame.origin.
 * Không tạo UIView màu đen để che.
 * Không scale toàn bộ UI.
 */
static void SC16ApplyCrop(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!window || window.hidden)
        return;

    if (!SC16IsApplicationWindow(window))
        return;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return;

    UIScreen *screen = scene.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGRect screenBounds = screen.bounds;

    CGFloat screenWidth =
        CGRectGetWidth(screenBounds);

    CGFloat screenHeight =
        CGRectGetHeight(screenBounds);

    if (screenWidth <= 0.0 ||
        screenHeight <= 0.0)
        return;

    CGRect bounds = window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 ||
        height <= 0.0)
        return;

    /*
     * Lưu center để UIWindow không bị đẩy xuống.
     */
    CGPoint center = window.center;

    /*
     * Tính crop theo chiều cao thực tế
     * của scene hiện tại.
     *
     * Khi xoay ngang, screenHeight thay đổi
     * nên crop được tính lại theo orientation mới.
     */
    CGFloat scaleY = height / screenHeight;

    if (scaleY <= 0.0)
        scaleY = 1.0;

    CGFloat topCrop =
        SC16_TOP_CROP * scaleY;

    CGFloat bottomCrop =
        SC16_BOTTOM_CROP * scaleY;

    CGFloat newHeight =
        height - topCrop - bottomCrop;

    if (newHeight <= 1.0)
        return;

    /*
     * Giữ nguyên chiều rộng.
     * Không scale ngang.
     */
    CGRect newBounds = bounds;

    /*
     * Cắt phần trên.
     */
    newBounds.origin.y += topCrop;

    /*
     * Cắt phần dưới.
     */
    newBounds.size.height = newHeight;

    /*
     * Thay đổi bounds để vùng đó thực sự
     * không còn nằm trong vùng hiển thị.
     */
    window.bounds = newBounds;

    /*
     * Giữ UIWindow ở đúng vị trí trung tâm.
     */
    window.center = center;

    /*
     * Không dùng transform scale.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Bo rất nhẹ 4 góc.
     */
    window.layer.cornerRadius =
        SC16_SCREEN_CORNER_RADIUS;

    window.layer.masksToBounds = YES;
}

/*
 * Áp dụng crop cho toàn bộ window
 * trong một UIWindowScene.
 */
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

        if (!SC16IsApplicationWindow(window))
            continue;

        if (window.hidden)
            continue;

        SC16ApplyCrop(window);
    }
}

/*
 * Áp dụng cho toàn bộ application scenes.
 */
static void SC16ReapplyAll(void) {
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    if (!application)
        return;

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
}

%hook UIWindow

/*
 * Khi window được hiển thị lần đầu.
 */
- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyCrop(self);
        }
    );
}

/*
 * UIKit thay đổi bounds khi orientation/layout
 * thay đổi.
 *
 * Không hook setFrame vì setFrame -> crop ->
 * setFrame có thể gây vòng lặp và lag.
 */
- (void)setBounds:(CGRect)newBounds {
    %orig(newBounds);

    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (self.windowScene &&
                SC16IsApplicationWindow(self) &&
                !self.hidden) {

                SC16ApplyCrop(self);
            }
        }
    );
}

%end

%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        /*
         * Áp dụng sau khi UIKit đã tạo window/scene.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ReapplyAll();
            }
        );

        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];

        /*
         * App trở lại active.
         */
        [center addObserverForName:
                    UIApplicationDidBecomeActiveNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(__unused NSNotification *notification) {

            SC16ReapplyAll();
        }];

        /*
         * Scene được activate.
         */
        [center addObserverForName:
                    UISceneDidActivateNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *notification) {

            UIScene *scene =
                notification.object;

            if (![scene isKindOfClass:
                        [UIWindowScene class]])
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
         * Khi app chuẩn bị mất active, không
         * chỉnh window để tránh can thiệp
         * Control Centre / Notification Center.
         */
        [center addObserverForName:
                    UIApplicationWillResignActiveNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(__unused NSNotification *notification) {
            /*
             * Intentionally empty.
             */
        }];
    }
}
