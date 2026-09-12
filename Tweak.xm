#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static CGFloat const SC16_SCREEN_CORNER_RADIUS = 2.0;
static CGFloat const SC16_MULTITASK_RADIUS = 2.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

/*
 * Chỉ crop content của window.
 *
 * QUAN TRỌNG:
 * Không thay đổi window.frame.origin.y.
 * Không đẩy toàn bộ UIWindow xuống dưới.
 *
 * Bounds được giảm lại và center giữ nguyên,
 * vì vậy phần trên/dưới thực sự bị loại khỏi vùng
 * hiển thị thay vì chỉ bị che bởi một vùng đen.
 */
static void SC16ApplyCropToWindow(UIWindow *window) {
    if (!window || window.hidden)
        return;

    if (!SC16Enabled())
        return;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return;

    UIScreen *screen = scene.screen ?: UIScreen.mainScreen;

    CGRect screenBounds = screen.bounds;

    CGFloat width = CGRectGetWidth(screenBounds);
    CGFloat height = CGRectGetHeight(screenBounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    /*
     * Orientation hiện tại được lấy trực tiếp từ UIWindowScene.
     *
     * Vì crop tính theo chiều cao hiện tại nên khi xoay:
     *
     * Portrait:
     *   top    = 34
     *   bottom = 34
     *
     * Landscape:
     *   vẫn áp dụng 34 ở hai cạnh theo trục dọc
     *   của màn hình hiện tại.
     */
    CGFloat cropTop = SC16_TOP_CROP;
    CGFloat cropBottom = SC16_BOTTOM_CROP;

    if (height <= cropTop + cropBottom)
        return;

    /*
     * Không scale hình.
     * Không kéo giãn.
     */
    window.transform = CGAffineTransformIdentity;

    /*
     * Lấy bounds hiện tại của window.
     */
    CGRect bounds = window.bounds;

    CGFloat originalHeight = CGRectGetHeight(bounds);
    CGFloat originalWidth = CGRectGetWidth(bounds);

    if (originalWidth <= 0.0 || originalHeight <= 0.0)
        return;

    /*
     * Tỷ lệ giữa coordinate space của window
     * và screen hiện tại.
     *
     * Điều này giúp tránh hard-code 34 theo một
     * kích thước duy nhất.
     */
    CGFloat scaleY = originalHeight / height;

    if (scaleY <= 0.0)
        scaleY = 1.0;

    CGFloat top = cropTop * scaleY;
    CGFloat bottom = cropBottom * scaleY;

    CGFloat newHeight = originalHeight - top - bottom;

    if (newHeight <= 0.0)
        return;

    /*
     * Thực sự cắt bounds.
     *
     * Không thay đổi center của window.
     */
    CGFloat centerY = CGRectGetMidY(bounds);

    bounds.origin.y += top;
    bounds.size.height = newHeight;

    window.bounds = bounds;

    /*
     * Giữ vùng hiển thị nằm chính giữa.
     */
    CGPoint center = window.center;
    center.y = centerY;
    window.center = center;

    /*
     * Bo rất nhẹ 4 góc.
     */
    window.layer.cornerRadius = SC16_SCREEN_CORNER_RADIUS;
    window.layer.masksToBounds = YES;

    /*
     * Không thêm shadow / overlay / black view.
     * Phần đã crop sẽ thực sự nằm ngoài bounds.
     */
}

/*
 * Xác định window nào thực sự thuộc ứng dụng.
 *
 * Không lấy các window hệ thống như Control Centre,
 * Notification Center, keyboard...
 */
static BOOL SC16IsAppWindow(UIWindow *window) {
    if (!window)
        return NO;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return NO;

    UISceneSession *session = scene.session;

    if (!session)
        return NO;

    NSString *role = session.role;

    if (role.length == 0)
        return NO;

    if (![role isEqualToString:UIWindowSceneSessionRoleApplication])
        return NO;

    return YES;
}

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!scene || !SC16Enabled())
        return;

    if (scene.activationState == UISceneActivationStateUnattached)
        return;

    NSArray<UIWindow *> *windows = scene.windows;

    for (UIWindow *window in windows) {

        if (!SC16IsAppWindow(window))
            continue;

        /*
         * Chỉ xử lý các window đang hiển thị.
         */
        if (window.hidden)
            continue;

        SC16ApplyCropToWindow(window);
    }
}

static void SC16ReapplyAll(void) {
    if (!SC16Enabled())
        return;

    UIApplication *app = UIApplication.sharedApplication;

    if (!app)
        return;

    NSSet<UIScene *> *scenes = app.connectedScenes;

    for (UIScene *scene in scenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        SC16ApplyScene(windowScene);
    }
}

/*
 * Reapply sau khi UIKit hoàn tất layout/orientation.
 *
 * Không gọi liên tục theo mỗi frame.
 * Chỉ chạy ở main queue khi cần.
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
 * Window xuất hiện.
 */
- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyCropToWindow(self);
    });
}

/*
 * UIKit có thể thay đổi bounds khi xoay màn hình.
 *
 * Không hook setFrame vì nó dễ tạo vòng lặp:
 *
 * setFrame
 *   -> crop
 *      -> setFrame
 *         -> crop
 *
 * gây giật/lag.
 */
- (void)setBounds:(CGRect)bounds {
    %orig(bounds);

    if (!SC16Enabled())
        return;

    /*
     * Chờ UIKit layout xong rồi crop lại.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.windowScene &&
            SC16IsAppWindow(self) &&
            !self.hidden) {

            SC16ApplyCropToWindow(self);
        }
    });
}

%end

%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        /*
         * Chờ UIKit khởi tạo scene/window.
         */
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ReapplyAll();
        });

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

            SC16ReapplyAll();
        }];

        /*
         * Scene active.
         */
        [center addObserverForName:
                    UISceneDidActivateNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *notification) {

            UIScene *scene = notification.object;

            if (![scene isKindOfClass:[UIWindowScene class]])
                return;

            /*
             * Đợi UIKit hoàn thành activation/layout.
             */
            dispatch_async(dispatch_get_main_queue(), ^{
                SC16ApplyScene((UIWindowScene *)scene);
            });
        }];

        /*
         * Scene thay đổi kích thước.
         *
         * Đây là điểm quan trọng cho xoay màn hình.
         */
        [center addObserverForName:
                    UIWindowSceneDidUpdateNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *notification) {

            UIScene *scene = notification.object;

            if (![scene isKindOfClass:[UIWindowScene class]])
                return;

            SC16ApplyScene((UIWindowScene *)scene);
        }];
    }
}
