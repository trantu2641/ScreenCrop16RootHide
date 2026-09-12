#import <UIKit/UIKit.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

static BOOL SC16Applying = NO;


/*
 * Tìm window ứng dụng thực sự đang hiển thị.
 */
static UIWindow *SC16ActiveWindowForScene(UIWindowScene *scene) {
    if (!scene)
        return nil;

    UIWindow *candidate = nil;

    for (UIWindow *window in scene.windows) {

        if (window.hidden)
            continue;

        if (window.alpha <= 0.01)
            continue;

        NSString *className =
            NSStringFromClass(window.class);

        /*
         * Không đụng vào keyboard/system windows.
         */
        if ([className containsString:@"Keyboard"])
            continue;

        if ([className containsString:@"TextEffects"])
            continue;

        /*
         * Ưu tiên key window.
         */
        if (window.isKeyWindow)
            return window;

        candidate = window;
    }

    return candidate;
}


/*
 * Crop UIWindow thật sự.
 *
 * Không dùng:
 * - layer.mask
 * - transform
 * - additionalSafeAreaInsets
 *
 * Window sẽ có frame mới:
 *
 * Portrait:
 *
 *  ┌──────────────────┐
 *  │    bỏ 34pt       │
 *  ├──────────────────┤
 *  │                  │
 *  │    APP CONTENT   │
 *  │                  │
 *  ├──────────────────┤
 *  │    bỏ 34pt       │
 *  └──────────────────┘
 */
static void SC16CropWindow(UIWindow *window) {

    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (SC16Applying)
        return;

    UIWindowScene *scene =
        window.windowScene;

    if (!scene)
        return;

    if (window.hidden)
        return;

    SC16Applying = YES;


    /*
     * Lấy kích thước của orientation hiện tại.
     *
     * Không dùng UIScreen.mainScreen.bounds cố định.
     */
    CGRect screenBounds =
        scene.coordinateSpace.bounds;

    CGFloat width =
        CGRectGetWidth(screenBounds);

    CGFloat height =
        CGRectGetHeight(screenBounds);

    if (width <= 0.0 || height <= 0.0) {
        SC16Applying = NO;
        return;
    }


    /*
     * Chiều cao vùng hiển thị sau khi crop.
     */
    CGFloat croppedHeight =
        height
        - SC16_TOP_CROP
        - SC16_BOTTOM_CROP;

    if (croppedHeight <= 0.0) {
        SC16Applying = NO;
        return;
    }


    /*
     * QUAN TRỌNG:
     *
     * Không scale.
     * Không transform.
     *
     * Đặt origin Y xuống 34pt
     * và giảm chiều cao window đi 68pt.
     */
    CGRect newFrame =
        CGRectMake(
            0.0,
            SC16_TOP_CROP,
            width,
            croppedHeight
        );


    /*
     * Chỉ thay đổi khi thực sự cần.
     * Tránh UIKit layout liên tục.
     */
    if (!CGRectEqualToRect(window.frame, newFrame)) {

        window.frame = newFrame;
    }


    /*
     * Bounds của window phải phản ánh
     * vùng hiển thị mới.
     */
    CGRect newBounds =
        CGRectMake(
            0.0,
            0.0,
            width,
            croppedHeight
        );

    if (!CGRectEqualToRect(window.bounds, newBounds)) {

        window.bounds = newBounds;
    }


    /*
     * Root view sử dụng toàn bộ UIWindow mới.
     */
    UIViewController *root =
        window.rootViewController;

    if (root) {

        root.view.frame =
            window.bounds;

        root.view.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;

        /*
         * Không cộng thêm safe-area.
         *
         * Vì window itself đã bị crop.
         */
        root.additionalSafeAreaInsets =
            UIEdgeInsetsZero;

        [root.view setNeedsLayout];
    }


    SC16Applying = NO;
}


/*
 * Áp dụng crop cho một scene.
 */
static void SC16ApplyScene(UIWindowScene *scene) {

    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;


    /*
     * Lấy window chính.
     */
    UIWindow *window =
        SC16ActiveWindowForScene(scene);

    if (window) {

        SC16CropWindow(window);
    }
}


/*
 * Áp dụng cho tất cả scene hiện tại.
 */
static void SC16ApplyAllScenes(void) {

    if (!SC16Enabled())
        return;

    UIApplication *app =
        UIApplication.sharedApplication;

    for (UIScene *scene in app.connectedScenes) {

        if (![scene isKindOfClass:
              [UIWindowScene class]]) {

            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        SC16ApplyScene(windowScene);
    }
}


/*
 * Re-apply sau khi UIKit hoàn thành
 * thay đổi orientation.
 */
static void SC16ApplyAfterRotation(void) {

    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*
             * Đợi thêm một vòng runloop để
             * scene có geometry mới hoàn chỉnh.
             */
            dispatch_async(
                dispatch_get_main_queue(),
                ^{

                    SC16ApplyAllScenes();
                }
            );
        }
    );
}


%hook UIWindow


/*
 * Khi app tạo window.
 */
- (void)makeKeyAndVisible {

    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SC16CropWindow(self);
        }
    );
}


%end



%ctor {

    @autoreleasepool {

        if (!SC16Enabled())
            return;


        /*
         * App khởi động.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{

                SC16ApplyAllScenes();
            }
        );


        /*
         * App trở lại active.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIApplicationDidBecomeActiveNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(__unused NSNotification *notification) {

                    SC16ApplyAllScenes();
                }];


        /*
         * Scene được activate.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(NSNotification *notification) {

                    UIScene *scene =
                        notification.object;

                    if ([scene isKindOfClass:
                         [UIWindowScene class]]) {

                        SC16ApplyScene(
                            (UIWindowScene *)scene
                        );
                    }
                }];


        /*
         * Xoay màn hình.
         *
         * Không lấy lại kích thước portrait.
         * Scene.coordinateSpace.bounds sẽ cung cấp
         * geometry hiện tại.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(__unused NSNotification *notification) {

                    SC16ApplyAfterRotation();
                }];


        /*
         * Window mới xuất hiện.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIWindowDidBecomeVisibleNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(NSNotification *notification) {

                    UIWindow *window =
                        notification.object;

                    if (![window isKindOfClass:
                          [UIWindow class]]) {

                        return;
                    }

                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{

                            SC16CropWindow(window);
                        }
                    );
                }];
    }
}
