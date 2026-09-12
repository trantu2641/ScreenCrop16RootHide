#import <UIKit/UIKit.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

static NSInteger const SC16_TAG = 0x53433136; // "SC16"


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


/*
 * Tìm container của ScreenCrop16.
 */
static UIView *SC16FindContainer(UIWindow *window) {
    for (UIView *view in window.subviews) {
        if (view.tag == SC16_TAG)
            return view;
    }

    return nil;
}


/*
 * Tạo container crop.
 *
 * Container này là vùng màn hình mà người dùng
 * thực sự nhìn thấy.
 */
static UIView *SC16CreateContainer(UIWindow *window) {

    UIView *container = SC16FindContainer(window);

    if (container)
        return container;

    container = [[UIView alloc] initWithFrame:CGRectZero];

    container.tag = SC16_TAG;

    container.backgroundColor = UIColor.blackColor;

    container.clipsToBounds = YES;

    container.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    /*
     * Đưa container lên trên các subview khác.
     */
    [window addSubview:container];

    return container;
}


/*
 * Áp dụng crop cho root view.
 */
static void SC16ApplyToWindow(UIWindow *window) {

    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (window.hidden)
        return;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

    /*
     * Không đụng window hệ thống.
     */
    if (window.windowLevel != UIWindowLevelNormal)
        return;

    UIViewController *rootVC =
        window.rootViewController;

    if (!rootVC)
        return;

    UIView *rootView = rootVC.view;

    if (!rootView)
        return;


    UIScreen *screen =
        scene.screen ?: UIScreen.mainScreen;

    CGRect screenBounds =
        screen.bounds;

    CGFloat width =
        CGRectGetWidth(screenBounds);

    CGFloat height =
        CGRectGetHeight(screenBounds);

    if (width <= 0.0 || height <= 0.0)
        return;


    BOOL portrait =
        SC16IsPortrait(scene);


    /*
     * Không dùng transform để scale.
     */
    window.transform =
        CGAffineTransformIdentity;


    UIView *container =
        SC16CreateContainer(window);


    /*
     * ============================
     * PORTRAIT
     * ============================
     *
     * 1284 × 2778
     *
     * Crop:
     *   top    34
     *   bottom 34
     *
     * Vùng hiển thị:
     *   1284 × 2710
     */
    if (portrait) {

        CGFloat contentHeight =
            height
            - SC16_TOP_CROP
            - SC16_BOTTOM_CROP;

        if (contentHeight <= 0.0)
            return;


        /*
         * Container nằm đúng vùng đã crop.
         */
        container.frame = CGRectMake(
            0.0,
            SC16_TOP_CROP,
            width,
            contentHeight
        );


        /*
         * Root view nằm trong container.
         *
         * Không scale.
         *
         * Y = -34:
         * phần 34px phía trên của root view
         * nằm ngoài container và bị clip.
         */
        rootView.frame = CGRectMake(
            0.0,
            -SC16_TOP_CROP,
            width,
            height
        );


    /*
     * ============================
     * LANDSCAPE
     * ============================
     *
     * 2778 × 1284
     *
     * Crop:
     *   left  34
     *   right 34
     *
     * Vùng hiển thị:
     *   2710 × 1284
     */
    } else {

        CGFloat contentWidth =
            width
            - SC16_TOP_CROP
            - SC16_BOTTOM_CROP;

        if (contentWidth <= 0.0)
            return;


        /*
         * Container nằm giữa màn hình.
         */
        container.frame = CGRectMake(
            SC16_TOP_CROP,
            0.0,
            contentWidth,
            height
        );


        /*
         * Root view dịch sang trái 34px.
         *
         * 34px bên trái và 34px bên phải
         * nằm ngoài container.
         */
        rootView.frame = CGRectMake(
            -SC16_TOP_CROP,
            0.0,
            width,
            height
        );
    }


    /*
     * Root view phải nằm trong container.
     */
    [rootView removeFromSuperview];

    [container addSubview:rootView];


    /*
     * Không để root view tự thay đổi geometry.
     */
    rootView.autoresizingMask = UIViewAutoresizingNone;


    /*
     * Ép UIKit layout lại.
     */
    [rootVC.view setNeedsLayout];
    [rootVC.view layoutIfNeeded];

    [container setNeedsLayout];
    [container layoutIfNeeded];
}


/*
 * Apply toàn bộ window trong scene.
 */
static void SC16ApplyScene(UIWindowScene *scene) {

    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;


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
 * Apply toàn bộ scene.
 */
static void SC16ApplyAllScenes(void) {

    if (!SC16Enabled())
        return;


    UIApplication *app =
        UIApplication.sharedApplication;


    for (UIScene *scene in app.connectedScenes) {

        if (![scene
              isKindOfClass:
              [UIWindowScene class]]) {

            continue;
        }


        SC16ApplyScene(
            (UIWindowScene *)scene
        );
    }
}


/*
 * ============================
 * UIWindow
 * ============================
 *
 * Chỉ bắt lúc window được hiển thị.
 *
 * Không hook setFrame.
 */
%hook UIWindow

- (void)makeKeyAndVisible {

    %orig;


    if (!SC16Enabled())
        return;


    UIWindow *window = self;


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            SC16ApplyToWindow(window);
        }
    );
}

%end


/*
 * ============================
 * UIViewController
 * ============================
 *
 * Khi UIKit thay đổi layout/orientation,
 * áp dụng lại crop sau layout.
 */
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {

    %orig(animated);


    if (!SC16Enabled())
        return;


    UIViewController *controller = self;


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            UIWindow *window =
                controller.view.window;

            if (window) {
                SC16ApplyToWindow(window);
            }
        }
    );
}

%end


/*
 * ============================
 * Constructor
 * ============================
 */
%ctor {

    @autoreleasepool {

        if (!SC16Enabled())
            return;


        /*
         * Chờ application khởi tạo xong.
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

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        SC16ApplyAllScenes();
                    }
                );
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

                UIScene *scene =
                    notification.object;


                if ([scene
                     isKindOfClass:
                     [UIWindowScene class]]) {

                    dispatch_async(
                        dispatch_get_main_queue(),
                        ^{

                        SC16ApplyScene(
                            (UIWindowScene *)scene
                        );
                    });
                }
            }];


        /*
         * Xoay màn hình.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(__unused NSNotification *notification) {

                /*
                 * Đợi UIKit cập nhật
                 * UIWindowScene trước khi crop.
                 */
                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(0.15 *
                            NSEC_PER_SEC)
                    ),
                    dispatch_get_main_queue(),
                    ^{

                        SC16ApplyAllScenes();
                    }
                );
            }];
    }
}
