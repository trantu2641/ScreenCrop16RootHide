#import <UIKit/UIKit.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

static BOOL SC16IsPortrait(UIWindowScene *scene) {
    if (!scene)
        return YES;

    UIInterfaceOrientation orientation =
        scene.interfaceOrientation;

    return UIInterfaceOrientationIsPortrait(orientation);
}

static void SC16ApplyToWindow(UIWindow *window) {
    if (!SC16Enabled() || !window || window.hidden)
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
     * Chỉ xử lý window ứng dụng bình thường.
     */
    if (window.windowLevel != UIWindowLevelNormal)
        return;

    /*
     * Không scale / không kéo giãn.
     */
    window.transform = CGAffineTransformIdentity;
    window.clipsToBounds = YES;

    BOOL portrait = SC16IsPortrait(scene);

    CGRect targetFrame;

    if (portrait) {

        /*
         * PORTRAIT
         *
         * 1284 × 2778
         *
         * Top    = 34 px
         * Bottom = 34 px
         *
         * Content = 1284 × 2710
         */

        CGFloat contentHeight =
            height
            - SC16_TOP_CROP
            - SC16_BOTTOM_CROP;

        if (contentHeight <= 0.0)
            return;

        targetFrame = CGRectMake(
            0.0,
            SC16_TOP_CROP,
            width,
            contentHeight
        );

    } else {

        /*
         * LANDSCAPE
         *
         * 2778 × 1284
         *
         * Tai thỏ / cạnh trên của máy khi dọc
         * trở thành cạnh trái khi xoay ngang.
         *
         * Crop trái  = 34 px
         * Crop phải  = 34 px
         *
         * Content = 2710 × 1284
         */

        CGFloat contentWidth =
            width
            - SC16_TOP_CROP
            - SC16_BOTTOM_CROP;

        if (contentWidth <= 0.0)
            return;

        targetFrame = CGRectMake(
            SC16_TOP_CROP,
            0.0,
            contentWidth,
            height
        );
    }

    /*
     * Đặt window vào vùng hiển thị đã crop.
     */
    if (!CGRectEqualToRect(window.frame, targetFrame)) {
        window.frame = targetFrame;
    }

    /*
     * Đưa root view vào đúng bounds mới.
     *
     * Không để UI cũ nằm ngoài vùng hiển thị
     * rồi bị thanh đen che.
     */
    UIViewController *rootVC =
        window.rootViewController;

    if (rootVC) {

        rootVC.view.frame = window.bounds;

        [rootVC.view setNeedsLayout];
        [rootVC.view layoutIfNeeded];
    }
}

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled() || !scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    for (UIWindow *window in scene.windows) {

        if (!window || window.hidden)
            continue;

        if (window.windowLevel != UIWindowLevelNormal)
            continue;

        SC16ApplyToWindow(window);
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

        SC16ApplyScene((UIWindowScene *)scene);
    }
}


/*
 * =========================
 * UIWindow
 * =========================
 *
 * Không hook setFrame:
 * tránh recursion và Safe Mode.
 */
%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *targetWindow = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyToWindow(targetWindow);
        }
    );
}

%end


/*
 * =========================
 * Constructor
 * =========================
 */
%ctor {
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        /*
         * Apply lần đầu.
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
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(__unused NSNotification *notification) {

                SC16ApplyAllScenes();
            }];


        /*
         * Scene active.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene
                     isKindOfClass:
                     [UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];


        /*
         * Xoay màn hình.
         *
         * Sau khi UIKit đổi orientation,
         * đọc lại scene.screen.bounds rồi
         * crop lại theo orientation mới.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(__unused NSNotification *notification) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        SC16ApplyAllScenes();
                    }
                );
            }];
    }
}
