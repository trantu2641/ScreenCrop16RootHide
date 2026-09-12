#import <UIKit/UIKit.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

static BOOL SC16Applying = NO;

static void SC16LayoutWindow(UIWindow *window) {
    if (!SC16Enabled() || !window || SC16Applying)
        return;

    UIWindowScene *scene = window.windowScene;
    if (!scene)
        return;

    if (window.hidden || window.alpha <= 0.01)
        return;

    SC16Applying = YES;

    /*
     * Lấy kích thước hiện tại của màn hình/scene.
     * Không dùng UIScreen.mainScreen cố định để
     * tránh lỗi khi xoay ngang.
     */
    CGRect screenBounds = scene.coordinateSpace.bounds;

    CGFloat screenWidth = CGRectGetWidth(screenBounds);
    CGFloat screenHeight = CGRectGetHeight(screenBounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0) {
        SC16Applying = NO;
        return;
    }

    /*
     * Crop theo CHIỀU DỌC của màn hình hiện tại.
     *
     * Portrait:
     *
     *       34
     *   ┌───────────┐
     *   │   CROP    │
     *   ├───────────┤
     *   │           │
     *   │    APP    │
     *   │           │
     *   ├───────────┤
     *   │   CROP    │
     *   └───────────┘
     *       34
     *
     * Landscape cũng dùng cùng nguyên tắc:
     * bỏ phần tương ứng ở hai cạnh trên/dưới
     * của orientation hiện tại.
     */

    BOOL landscape = screenWidth > screenHeight;

    CGFloat topCrop = SC16_TOP_CROP;
    CGFloat bottomCrop = SC16_BOTTOM_CROP;

    CGFloat newWidth = screenWidth;
    CGFloat newHeight = screenHeight - topCrop - bottomCrop;

    if (newHeight <= 0.0) {
        SC16Applying = NO;
        return;
    }

    /*
     * Lưu orientation hiện tại bằng scene geometry.
     */
    CGRect newFrame;

    if (!landscape) {
        /*
         * Portrait
         */
        newFrame = CGRectMake(
            0.0,
            topCrop,
            newWidth,
            newHeight
        );
    } else {
        /*
         * Landscape:
         *
         * KHÔNG xoay frame thủ công.
         * scene.coordinateSpace đã trả về
         * orientation hiện tại.
         *
         * Vẫn cắt 34 phía trên và 34 phía dưới
         * theo hệ tọa độ landscape.
         */
        newFrame = CGRectMake(
            0.0,
            topCrop,
            newWidth,
            newHeight
        );
    }

    /*
     * Chỉ thay đổi frame khi thực sự khác.
     * Điều này tránh layout loop / lag.
     */
    CGRect currentFrame = window.frame;

    if (!CGRectEqualToRect(currentFrame, newFrame)) {
        window.frame = newFrame;
    }

    /*
     * Window đã bị thu nhỏ thật.
     * Root view phải sử dụng toàn bộ bounds mới,
     * không cộng thêm crop lần nữa.
     */
    UIViewController *root = window.rootViewController;

    if (root) {
        root.additionalSafeAreaInsets = UIEdgeInsetsZero;

        root.view.frame = window.bounds;
        root.view.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;

        [root.view setNeedsLayout];
        [root.view layoutIfNeeded];
    }

    SC16Applying = NO;
}

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled() || !scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    /*
     * Chỉ xử lý window ứng dụng.
     */
    for (UIWindow *window in scene.windows) {

        if (window.hidden)
            continue;

        if (window.alpha <= 0.01)
            continue;

        NSString *className =
            NSStringFromClass(window.class);

        if ([className containsString:@"Keyboard"])
            continue;

        if ([className containsString:@"TextEffects"])
            continue;

        if (window.rootViewController) {
            SC16LayoutWindow(window);
        }
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

        SC16ApplyScene(
            (UIWindowScene *)scene
        );
    }
}

static void SC16Reapply(void) {
    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();
        }
    );
}

%hook UIWindow

/*
 * Window được tạo.
 */
- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16LayoutWindow(self);
        }
    );
}

%end

%hook UIViewController

/*
 * Không hook setFrame của UIWindow.
 *
 * Chỉ layout lại root view sau khi UIKit hoàn tất
 * layout bình thường.
 */
- (void)viewDidLayoutSubviews {
    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *window = self.view.window;

    if (!window)
        return;

    if (self == window.rootViewController &&
        !SC16Applying) {

        /*
         * Không gọi lại ngay trong layout hiện tại.
         * Đưa sang runloop kế tiếp để tránh vòng lặp.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                if (!SC16Applying) {
                    SC16LayoutWindow(window);
                }
            }
        );
    }
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
         * App active.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *note) {

                SC16ApplyAllScenes();
            }];

        /*
         * Scene active.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {

                UIScene *scene = note.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

        /*
         * Xoay màn hình.
         *
         * Lấy lại scene.coordinateSpace sau khi
         * orientation thay đổi.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *note) {

                /*
                 * Đợi UIKit hoàn tất rotation rồi
                 * mới tính geometry mới.
                 */
                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAllScenes();
                    }
                );
            }];

        /*
         * Khi window mới xuất hiện.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIWindowDidBecomeVisibleNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {

                UIWindow *window = note.object;

                if (![window isKindOfClass:[UIWindow class]])
                    return;

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        SC16LayoutWindow(window);
                    }
                );
            }];
    }
}
