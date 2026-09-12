#import <UIKit/UIKit.h>

#pragma mark - Configuration

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;
static CGFloat const SC16_CORNER_RADIUS = 2.0;

#pragma mark - State

static NSMutableDictionary *SC16OriginalFrames = nil;
static NSMutableDictionary *SC16OriginalBounds = nil;
static NSMutableDictionary *SC16OriginalTransforms = nil;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

#pragma mark - Helpers

static BOOL SC16IsSystemWindow(UIWindow *window) {
    if (!window)
        return YES;

    NSString *className = NSStringFromClass(window.class);

    /*
     * Không đụng vào các cửa sổ hệ thống đặc biệt.
     * Đặc biệt tránh làm hỏng Control Center / Notification UI.
     */
    if ([className containsString:@"UITextEffectsWindow"])
        return YES;

    if ([className containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([className containsString:@"_UIStatusBar"])
        return YES;

    if ([className containsString:@"StatusBar"])
        return YES;

    if ([className containsString:@"Keyboard"])
        return YES;

    return NO;
}

static NSString *SC16WindowKey(UIWindow *window) {
    return [NSString stringWithFormat:@"%p", window];
}

static CGRect SC16ScreenBoundsForWindow(UIWindow *window) {
    if (!window)
        return CGRectZero;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    /*
     * screen.bounds luôn lấy kích thước theo orientation hiện tại
     * của màn hình, không cố định portrait.
     */
    return screen.bounds;
}

#pragma mark - Crop

static void SC16ApplyCrop(UIWindow *window) {
    if (!SC16Enabled() || !window)
        return;

    /*
     * Không xử lý keyboard / system windows.
     */
    if (SC16IsSystemWindow(window))
        return;

    /*
     * Chỉ xử lý window đang thực sự được hiển thị.
     */
    if (window.hidden || window.alpha <= 0.0)
        return;

    CGRect screenBounds = SC16ScreenBoundsForWindow(window);

    CGFloat screenWidth = CGRectGetWidth(screenBounds);
    CGFloat screenHeight = CGRectGetHeight(screenBounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0)
        return;

    CGFloat topCrop = SC16_TOP_CROP;
    CGFloat bottomCrop = SC16_BOTTOM_CROP;

    /*
     * Khi xoay ngang, crop vẫn được tính theo cạnh trên / dưới
     * của orientation hiện tại.
     */
    if (screenHeight <= topCrop + bottomCrop)
        return;

    NSString *key = SC16WindowKey(window);

    if (!SC16OriginalFrames[key])
        SC16OriginalFrames[key] = [NSValue valueWithCGRect:window.frame];

    if (!SC16OriginalBounds[key])
        SC16OriginalBounds[key] = [NSValue valueWithCGRect:window.bounds];

    if (!SC16OriginalTransforms[key])
        SC16OriginalTransforms[key] =
            [NSValue valueWithCGAffineTransform:window.transform];

    /*
     * Không dùng frame để "đẩy" toàn bộ UIWindow.
     *
     * Việc thay frame trực tiếp trước đây khiến UIKit layout lại
     * safe-area theo frame mới, dẫn tới:
     *
     * - UI bị đẩy xuống
     * - đáy bị che
     * - landscape sai
     *
     * Ở đây giữ window ở đúng vị trí và dùng bounds + transform
     * để hiển thị vùng nội dung đã crop.
     */

    window.transform = CGAffineTransformIdentity;

    CGRect bounds = window.bounds;

    CGFloat originalWidth = CGRectGetWidth(bounds);
    CGFloat originalHeight = CGRectGetHeight(bounds);

    if (originalWidth <= 0.0 || originalHeight <= 0.0)
        return;

    /*
     * Tỷ lệ 1:1 theo trục.
     *
     * Không kéo méo hình.
     * Crop 34px phía trên + 34px phía dưới.
     */
    CGFloat visibleHeight =
        originalHeight - topCrop - bottomCrop;

    if (visibleHeight <= 0.0)
        return;

    /*
     * Dịch vùng nội dung lên để phần bị crop nằm ngoài vùng hiển thị,
     * thay vì resize frame của UIWindow.
     */
    CGRect newBounds = bounds;

    newBounds.origin.x = CGRectGetMinX(bounds);

    newBounds.origin.y =
        CGRectGetMinY(bounds) + topCrop;

    newBounds.size.width = originalWidth;
    newBounds.size.height = visibleHeight;

    /*
     * Giữ tâm hiển thị.
     */
    CGPoint center = window.center;

    window.bounds = newBounds;
    window.center = center;

    /*
     * UIKit có thể tự layout lại window sau khi bounds thay đổi.
     * Ép layout ngay để tránh hiện tượng UI bị trôi.
     */
    [window setNeedsLayout];
    [window layoutIfNeeded];
}

#pragma mark - Rounded corners

static void SC16ApplyCorners(UIWindow *window) {
    if (!window)
        return;

    if (SC16IsSystemWindow(window))
        return;

    /*
     * Bo rất nhẹ: 2px.
     * Không dùng corner radius lớn để tránh tạo cảm giác
     * màn hình bị bo quá mức.
     */
    window.layer.cornerRadius = SC16_CORNER_RADIUS;
    window.layer.masksToBounds = YES;
}

#pragma mark - Apply

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
     * Không sử dụng UIApplication.windows vì API này deprecated
     * từ iOS 15 và build đang dùng -Werror.
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

    UIApplication *app = UIApplication.sharedApplication;

    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        UISceneActivationState state =
            windowScene.activationState;

        if (state == UISceneActivationStateUnattached)
            continue;

        SC16ApplyScene(windowScene);
    }
}

#pragma mark - Reapply

static void SC16ScheduleReapply(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyAllScenes();
    });
}

#pragma mark - UIWindow

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyWindow(self);
    });
}

- (void)setFrame:(CGRect)frame {
    /*
     * Cho UIKit xử lý frame trước.
     */
    %orig(frame);

    if (!SC16Enabled())
        return;

    /*
     * Không crop ngay trong setFrame.
     * UIKit thường gọi setFrame rất nhiều lần trong quá trình
     * rotation / transition. Crop ngay tại đây sẽ gây giật.
     */
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

- (void)setBounds:(CGRect)bounds {
    %orig(bounds);

    if (!SC16Enabled())
        return;

    /*
     * Chờ UIKit hoàn tất layout rồi mới áp dụng crop.
     * Tránh vòng lặp layout.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.hidden)
            SC16ApplyWindow(self);
    });
}

%end

#pragma mark - Rotation / Scene

%hook UIWindowScene

- (void)setInterfaceOrientation:(UIInterfaceOrientation)orientation {
    %orig(orientation);

    if (!SC16Enabled())
        return;

    /*
     * Không crop trong lúc orientation đang transition.
     * Chờ UIKit chuyển orientation xong.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyScene(self);

        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyScene(self);
        });
    });
}

%end

#pragma mark - UIApplication lifecycle

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
         * Initial apply.
         */
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyAllScenes();
        });

        /*
         * App active.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ApplyAllScenes();
            }];

        /*
         * Scene active.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    SC16ApplyScene((UIWindowScene *)scene);
                }
            }];

        /*
         * Scene will enter foreground.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneWillEnterForegroundNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    SC16ApplyScene((UIWindowScene *)scene);
                }
            }];

        /*
         * Orientation / size thay đổi.
         *
         * Không dùng UIWindowSceneDidUpdateNotification vì symbol này
         * không tồn tại trong SDK đang build.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                /*
                 * Chờ rotation hoàn thành.
                 */
                dispatch_async(dispatch_get_main_queue(), ^{
                    SC16ApplyAllScenes();

                    dispatch_async(dispatch_get_main_queue(), ^{
                        SC16ApplyAllScenes();
                    });
                });
            }];
    }
}
