#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - Configuration

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;
static CGFloat const SC16_MULTITASK_RADIUS = 2.0;

#pragma mark - Helpers

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;

    /*
     * Chỉ chạy trên iOS 16.4.x.
     */
    return [version hasPrefix:@"16.4"];
}

static BOOL SC16IsSystemWindow(UIWindow *window) {
    if (!window)
        return YES;

    NSString *className = NSStringFromClass(window.class);

    /*
     * Không đụng vào các window hệ thống.
     */
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

    if ([className containsString:@"ControlCenter"])
        return YES;

    if ([className containsString:@"Notification"])
        return YES;

    if ([className containsString:@"SpringBoard"])
        return YES;

    return NO;
}

static UIWindowScene *SC16WindowSceneForWindow(UIWindow *window) {
    if (!window)
        return nil;

    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = window.windowScene;

        if (scene)
            return scene;
    }

    return nil;
}

static CGRect SC16SceneBounds(UIWindowScene *scene) {
    if (!scene)
        return CGRectZero;

    return scene.coordinateSpace.bounds;
}

static BOOL SC16IsPortraitScene(UIWindowScene *scene) {
    if (!scene)
        return YES;

    CGSize size = SC16SceneBounds(scene).size;

    return size.height >= size.width;
}

#pragma mark - Crop

static void SC16ApplyCrop(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (SC16IsSystemWindow(window))
        return;

    if (window.hidden)
        return;

    if (window.alpha <= 0.0)
        return;

    UIWindowScene *scene = SC16WindowSceneForWindow(window);

    if (!scene)
        return;

    if (scene.activationState == UISceneActivationStateUnattached)
        return;

    CGRect sceneBounds = SC16SceneBounds(scene);

    CGFloat sceneWidth = CGRectGetWidth(sceneBounds);
    CGFloat sceneHeight = CGRectGetHeight(sceneBounds);

    if (sceneWidth <= 0.0 || sceneHeight <= 0.0)
        return;

    CGRect originalBounds = window.bounds;

    CGFloat width = CGRectGetWidth(originalBounds);
    CGFloat height = CGRectGetHeight(originalBounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    /*
     * Quan trọng:
     *
     * Không dùng transform scale.
     * Không scale X/Y.
     * Không thay đổi window.center.
     *
     * Chỉ thay đổi vùng hiển thị của UIWindow.
     */

    CGFloat topCrop = SC16_TOP_CROP;
    CGFloat bottomCrop = SC16_BOTTOM_CROP;

    /*
     * Khi xoay ngang:
     *
     * sceneBounds thường trở thành:
     *
     * width  = 2778
     * height = 1248
     *
     * Crop vẫn tính theo cạnh ngắn đang hiển thị,
     * tức 34px trên và 34px dưới theo orientation hiện tại.
     */
    if (SC16IsPortraitScene(scene)) {
        if (height <= topCrop + bottomCrop)
            return;
    } else {
        if (height <= topCrop + bottomCrop)
            return;
    }

    CGFloat croppedHeight =
        height - topCrop - bottomCrop;

    if (croppedHeight <= 0.0)
        return;

    /*
     * Lưu vị trí gốc của bounds.
     */
    CGFloat oldMinY = CGRectGetMinY(originalBounds);

    /*
     * Crop thật vùng trên + dưới.
     *
     * Không scale nội dung.
     * Không thay đổi center.
     */
    CGRect newBounds = originalBounds;

    newBounds.origin.y = oldMinY + topCrop;
    newBounds.size.height = croppedHeight;

    /*
     * Chỉ thay đổi nếu thực sự khác.
     * Tránh layout loop / lag.
     */
    if (!CGRectEqualToRect(window.bounds, newBounds)) {
        window.bounds = newBounds;
    }

    [window setNeedsLayout];
}

#pragma mark - Multitasking Corners

static void SC16ApplyMultitaskCorner(UIWindow *window) {
    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (SC16IsSystemWindow(window))
        return;

    /*
     * Chỉ giữ góc multitasking rất nhẹ.
     *
     * Không dùng transform.
     * Không scale màn hình.
     */
    window.layer.cornerRadius = SC16_MULTITASK_RADIUS;
    window.layer.masksToBounds = YES;
}

#pragma mark - Window Apply

static void SC16ApplyWindow(UIWindow *window) {
    if (!window)
        return;

    if (!SC16Enabled())
        return;

    if (SC16IsSystemWindow(window))
        return;

    SC16ApplyCrop(window);
    SC16ApplyMultitaskCorner(window);
}

#pragma mark - Scene Apply

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState == UISceneActivationStateUnattached)
        return;

    /*
     * scene.windows là API đúng cho iOS 15+.
     */
    NSArray<UIWindow *> *windows = scene.windows;

    for (UIWindow *window in windows) {
        if (!window)
            continue;

        if (window.hidden)
            continue;

        SC16ApplyWindow(window);
    }
}

static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    if (!application)
        return;

    NSSet<UIScene *> *connectedScenes =
        application.connectedScenes;

    for (UIScene *scene in connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        SC16ApplyScene(windowScene);
    }
}

#pragma mark - Delayed Apply

static void SC16ScheduleReapply(void) {
    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        SC16ApplyAllScenes();

        /*
         * UIKit có thể hoàn thành layout/rotation
         * ở lượt runloop tiếp theo.
         */
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyAllScenes();
        });
    });
}

#pragma mark - UIWindow Hook

/*
 * %hook bắt buộc nằm ngoài mọi function/block/%ctor.
 */

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.hidden)
            SC16ApplyWindow(self);
    });
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);

    if (!SC16Enabled())
        return;

    if (hidden)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.hidden)
            SC16ApplyWindow(self);
    });
}

- (void)setFrame:(CGRect)frame {
    %orig(frame);

    if (!SC16Enabled())
        return;

    /*
     * Không crop trực tiếp trong setFrame.
     * Tránh vòng lặp layout.
     */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.hidden)
            SC16ApplyWindow(self);
    });
}

%end

#pragma mark - Constructor

%ctor {
    @autoreleasepool {

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
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ScheduleReapply();
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

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

        /*
         * Scene foreground.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneWillEnterForegroundNotification
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
         * Rotation.
         *
         * Không dùng UIWindowSceneDidUpdateNotification
         * vì symbol đó không tồn tại trong SDK đang build.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ScheduleReapply();
            }];
    }
}
