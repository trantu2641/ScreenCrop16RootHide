#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static CGFloat const SC16_SCREEN_CORNER_RADIUS = 2.0;
static CGFloat const SC16_MULTITASK_RADIUS = 2.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

/*
 * Kiểm tra đây có phải window của application hay không.
 * Không đụng vào các window hệ thống như Control Centre /
 * Notification Center.
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
 * Không:
 *   - đổi frame.origin.y
 *   - scale méo
 *   - tạo UIView màu đen để che
 *
 * Window vẫn nằm ở đúng vị trí trung tâm.
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

    CGFloat screenWidth = CGRectGetWidth(screenBounds);
    CGFloat screenHeight = CGRectGetHeight(screenBounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0)
        return;

    CGRect bounds = window.bounds;

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    /*
     * Lưu center hiện tại.
     * Không thay đổi vị trí window.
     */
    CGPoint center = window.center;

    /*
     * Tỷ lệ giữa window coordinate và screen coordinate.
     *
     * Điều này giúp 34px vẫn tương ứng với 34px
     * màn hình thay vì scale toàn bộ UI.
     */
    CGFloat scaleY = height / screenHeight;

    if (scaleY <= 0.0)
        scaleY = 1.0;

    CGFloat topCrop = SC16_TOP_CROP * scaleY;
    CGFloat bottomCrop = SC16_BOTTOM_CROP * scaleY;

    CGFloat newHeight = height - topCrop - bottomCrop;

    if (newHeight <= 1.0)
        return;

    /*
     * Chỉ thay đổi bounds.
     *
     * Đây là phần crop thật.
     */
    CGRect newBounds = bounds;

    newBounds.origin.y += topCrop;
    newBounds.size.height = newHeight;

    window.bounds = newBounds;

    /*
     * Đưa center trở lại đúng vị trí.
     */
    window.center = center;

    /*
     * Không dùng transform scale.
     * UI giữ tỷ lệ 1:1, không méo.
     */
    window.transform = CGAffineTransformIdentity;

    /*
     * Bo rất nhẹ 4 góc.
     */
    window.layer.cornerRadius =
        SC16_SCREEN_CORNER_RADIUS;

    window.layer.masksToBounds = YES;
}

/*
 * Áp dụng cho một scene.
 */
static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    NSArray<UIWindow *> *windows = scene.windows;

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

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        SC16ApplyScene(windowScene);
    }
}

/*
 * Đợi UIKit hoàn thành layout rồi mới crop.
 *
 * Không chạy mỗi frame nên tránh lag.
 */
static void SC16ScheduleReapply(void) {
    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ReapplyAll();
    });
}

%hook UIWindow

/*
 * Window vừa hiện.
 */
- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyCrop(self);
    });
}

/*
 * Không hook setFrame:
 *
 * setFrame -> crop -> setFrame -> crop
 *
 * có thể tạo vòng lặp và gây giật/lag.
 *
 * Chỉ xử lý bounds khi UIKit thay đổi kích thước.
 */
- (void)setBounds:(CGRect)newBounds {
    %orig(newBounds);

    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyCrop(self);
    });
}

%end

%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        /*
         * Lần đầu khi tweak được load.
         */
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ReapplyAll();
        });

        NSNotificationCenter *center =
            [NSNotificationCenter defaultCenter];

        /*
         * App active trở lại.
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

            UIScene *scene = notification.object;

            if (![scene isKindOfClass:[UIWindowScene class]])
                return;

            dispatch_async(dispatch_get_main_queue(), ^{
                SC16ApplyScene(
                    (UIWindowScene *)scene
                );
            });
        }];

        /*
         * Scene chuyển trạng thái / thay đổi kích thước.
         *
         * Không dùng UIWindowSceneDidUpdateNotification
         * vì symbol đó không tồn tại trong SDK đang build.
         *
         * UIApplicationDidBecomeActive +
         * UISceneDidActivate + setBounds là đủ để
         * reapply khi orientation/layout thay đổi.
         */
        [center addObserverForName:
                    UIApplicationWillResignActiveNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(__unused NSNotification *notification) {

            /*
             * Không làm gì khi resign active.
             * Tránh can thiệp Control Centre.
             */
        }];
    }
}
