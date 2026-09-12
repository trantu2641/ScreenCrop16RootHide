#import <UIKit/UIKit.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;


/*
 * Chỉ chạy trên iOS 16.4
 */
static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}


/*
 * Xác định orientation hiện tại của Scene.
 */
static BOOL SC16IsPortrait(UIWindowScene *scene) {
    if (!scene)
        return YES;

    UIInterfaceOrientation orientation =
        scene.interfaceOrientation;

    return UIInterfaceOrientationIsPortrait(orientation);
}


/*
 * Crop một UIWindow.
 *
 * PORTRAIT:
 *   1284 × 2778
 *   top    = 34
 *   bottom = 34
 *   content = 1284 × 2710
 *
 * LANDSCAPE:
 *   2778 × 1284
 *   left  = 34
 *   right = 34
 *   content = 2710 × 1284
 */
static void SC16ApplyToWindow(UIWindow *window) {

    if (!SC16Enabled())
        return;

    if (!window || window.hidden)
        return;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return;

    UIScreen *screen =
        scene.screen ?: UIScreen.mainScreen;

    CGRect screenBounds = screen.bounds;

    CGFloat width =
        CGRectGetWidth(screenBounds);

    CGFloat height =
        CGRectGetHeight(screenBounds);

    if (width <= 0.0 || height <= 0.0)
        return;


    /*
     * Chỉ xử lý window ứng dụng bình thường.
     *
     * Không đụng:
     * - keyboard
     * - alert
     * - system overlay
     * - các window đặc biệt
     */
    if (window.windowLevel != UIWindowLevelNormal)
        return;


    /*
     * Không scale.
     */
    window.transform = CGAffineTransformIdentity;

    window.clipsToBounds = YES;


    BOOL portrait =
        SC16IsPortrait(scene);

    CGRect targetFrame;


    if (portrait) {

        /*
         * ==========================
         * PORTRAIT
         * ==========================
         *
         * 1284 × 2778
         *
         *       34 px
         *     ┌───────────┐
         *     │   CROP    │
         *     ├───────────┤
         *     │           │
         *     │  CONTENT  │
         *     │           │
         *     ├───────────┤
         *     │   CROP    │
         *     └───────────┘
         *       34 px
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
         * ==========================
         * LANDSCAPE
         * ==========================
         *
         * 2778 × 1284
         *
         *     34px                 34px
         *       ↓                     ↓
         *   ┌────┬────────────────────┬────┐
         *   │CROP│      CONTENT       │CROP│
         *   │    │                    │    │
         *   └────┴────────────────────┴────┘
         *
         * Content:
         *   2710 × 1284
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
     * Chỉ thay frame khi thực sự khác.
     */
    if (!CGRectEqualToRect(
            window.frame,
            targetFrame)) {

        window.frame = targetFrame;
    }


    /*
     * QUAN TRỌNG:
     *
     * Root view phải nhận bounds mới.
     *
     * Như vậy UI được layout trong vùng
     * đã crop, thay vì giữ layout cũ rồi
     * bị một vùng đen che lên.
     */
    UIViewController *rootVC =
        window.rootViewController;

    if (rootVC) {

        rootVC.view.frame =
            window.bounds;

        [rootVC.view setNeedsLayout];

        [rootVC.view layoutIfNeeded];
    }
}


/*
 * Apply cho toàn bộ window trong một Scene.
 */
static void SC16ApplyScene(UIWindowScene *scene) {

    if (!SC16Enabled())
        return;

    if (!scene)
        return;


    if (scene.activationState ==
        UISceneActivationStateUnattached) {

        return;
    }


    for (UIWindow *window in scene.windows) {

        if (!window)
            continue;

        if (window.hidden)
            continue;

        if (window.windowLevel != UIWindowLevelNormal)
            continue;

        SC16ApplyToWindow(window);
    }
}


/*
 * Apply cho toàn bộ Scene hiện tại.
 */
static void SC16ApplyAllScenes(void) {

    if (!SC16Enabled())
        return;


    UIApplication *app =
        UIApplication.sharedApplication;


    for (UIScene *scene in app.connectedScenes) {

        if (![scene
              isKindOfClass:[UIWindowScene class]]) {

            continue;
        }


        UIWindowScene *windowScene =
            (UIWindowScene *)scene;


        SC16ApplyScene(windowScene);
    }
}


/*
 * ==========================
 * UIWindow
 * ==========================
 *
 * Chỉ hook makeKeyAndVisible.
 *
 * KHÔNG hook setFrame:
 * vì UIKit có thể gọi setFrame liên tục
 * trong quá trình rotation/layout.
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
 * ==========================
 * UIWindowScene
 * ==========================
 *
 * Khi Scene thay đổi geometry,
 * apply lại crop sau khi UIKit xử lý.
 */
%hook UIWindowScene

- (void)requestGeometryUpdateWithPreferences:
    (UIWindowSceneGeometryPreferences *)preferences
    errorHandler:
    (void (^)(NSError *error))errorHandler {

    %orig(
        preferences,
        errorHandler
    );


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SC16ApplyScene(self);
        }
    );
}

%end


/*
 * ==========================
 * Constructor
 * ==========================
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
         * App trở lại foreground.
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
         * Scene vừa active.
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


                if ([scene
                     isKindOfClass:
                     [UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];


        /*
         * Orientation thay đổi.
         *
         * Đợi UIKit hoàn tất rotation rồi
         * lấy lại screen.bounds mới.
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
