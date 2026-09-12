#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat SC16_TOP = 34.0;
static const CGFloat SC16_BOTTOM = 34.0;

static BOOL SC16Enabled(void) {
    NSString *v = UIDevice.currentDevice.systemVersion;
    return [v hasPrefix:@"16.4"];
}

static UIWindow *SC16WindowForView(UIView *view) {
    if (!view)
        return nil;

    UIWindow *window = view.window;

    if (window)
        return window;

    UIView *parent = view.superview;

    while (parent) {
        if ([parent isKindOfClass:[UIWindow class]])
            return (UIWindow *)parent;

        parent = parent.superview;
    }

    return nil;
}

static BOOL SC16Portrait(UIWindow *window) {
    UIWindowScene *scene = window.windowScene;

    if (scene) {
        UIInterfaceOrientation o =
            scene.interfaceOrientation;

        if (o != UIInterfaceOrientationUnknown)
            return UIInterfaceOrientationIsPortrait(o);
    }

    return window.bounds.size.height >=
           window.bounds.size.width;
}


/*
 * Chỉ crop phần hiển thị.
 *
 * Dọc:
 *   top 34
 *   bottom 34
 *
 * Ngang:
 *   giữ cùng logic theo hai cạnh tương ứng
 *   của màn hình hiện tại.
 */
static void SC16ApplyWindowMask(UIWindow *window) {

    if (!window)
        return;

    CGFloat w = window.bounds.size.width;
    CGFloat h = window.bounds.size.height;

    if (w <= 0 || h <= 0)
        return;

    BOOL portrait = SC16Portrait(window);

    CGRect visible;

    if (portrait) {

        visible = CGRectMake(
            0,
            SC16_TOP,
            w,
            h - SC16_TOP - SC16_BOTTOM
        );

    } else {

        visible = CGRectMake(
            SC16_TOP,
            0,
            w - SC16_TOP - SC16_BOTTOM,
            h
        );
    }

    if (visible.size.width <= 0 ||
        visible.size.height <= 0)
        return;

    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame = window.bounds;

    mask.path =
        [UIBezierPath
            bezierPathWithRect:visible].CGPath;

    window.layer.mask = mask;
}


/*
 * Đây là phần quan trọng:
 *
 * root view KHÔNG còn có kích thước toàn màn hình.
 *
 * Dọc:
 *
 * window
 * ┌──────────────────┐
 * │      34px        │
 * ├──────────────────┤
 * │                  │
 * │     ROOT VIEW    │
 * │     2710px       │
 * │                  │
 * └──────────────────┘
 *        34px
 *
 * UIKit sẽ layout UI trong vùng 2710px,
 * vì vậy bottom UI không chỉ bị thanh đen che.
 */
static void SC16ApplyRootView(UIWindow *window) {

    if (!window)
        return;

    UIViewController *root =
        window.rootViewController;

    if (!root)
        return;

    UIView *view = root.view;

    if (!view)
        return;

    CGFloat w = window.bounds.size.width;
    CGFloat h = window.bounds.size.height;

    if (w <= 0 || h <= 0)
        return;

    BOOL portrait = SC16Portrait(window);

    CGRect frame;

    if (portrait) {

        frame = CGRectMake(
            0,
            SC16_TOP,
            w,
            h - SC16_TOP - SC16_BOTTOM
        );

    } else {

        frame = CGRectMake(
            SC16_TOP,
            0,
            w - SC16_TOP - SC16_BOTTOM,
            h
        );
    }

    if (frame.size.width <= 0 ||
        frame.size.height <= 0)
        return;

    /*
     * Không scale.
     */
    view.transform =
        CGAffineTransformIdentity;

    /*
     * Cho root view có đúng kích thước
     * vùng màn hình sau crop.
     */
    view.frame = frame;

    /*
     * Ngăn view tự kéo trở lại full window.
     */
    view.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    /*
     * Safe area của root view phải tính từ
     * vùng đã crop, không phải từ notch thật.
     */
    if (@available(iOS 11.0, *)) {
        root.additionalSafeAreaInsets =
            UIEdgeInsetsZero;
    }
}


/*
 * Apply sau khi UIKit hoàn thành layout.
 */
static void SC16Apply(UIWindow *window) {

    if (!SC16Enabled())
        return;

    if (!window)
        return;

    if (window.hidden)
        return;

    if (!window.rootViewController)
        return;

    /*
     * Thứ tự rất quan trọng:
     *
     * 1. window vẫn giữ nguyên bounds
     * 2. root view giảm kích thước
     * 3. window mask cắt phần ngoài
     */
    SC16ApplyRootView(window);

    SC16ApplyWindowMask(window);

    [window.rootViewController.view
        setNeedsLayout];

    [window.rootViewController.view
        layoutIfNeeded];
}


static void SC16ApplyAll(void) {

    if (!SC16Enabled())
        return;

    UIApplication *app =
        UIApplication.sharedApplication;

    if (!app)
        return;

    for (UIScene *scene in app.connectedScenes) {

        if (![scene
            isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *ws =
            (UIWindowScene *)scene;

        if (ws.activationState ==
            UISceneActivationStateUnattached)
            continue;

        for (UIWindow *window in ws.windows) {

            if (!window)
                continue;

            if (window.windowLevel !=
                UIWindowLevelNormal)
                continue;

            SC16Apply(window);
        }
    }
}


/*
 * ==========================================
 * UIWindow
 * ==========================================
 *
 * Không hook setFrame.
 *
 * Chỉ apply sau các thời điểm UIKit
 * thay đổi geometry.
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
            SC16Apply(window);
        }
    );
}

- (void)setRootViewController:
    (UIViewController *)vc {

    %orig(vc);

    if (!SC16Enabled())
        return;

    UIWindow *window = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16Apply(window);
        }
    );
}

- (void)layoutSubviews {

    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *window = self;

    /*
     * UIKit vừa layout window xong.
     * Ép crop lại ngay sau đó.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16Apply(window);
        }
    );
}

%end


/*
 * ==========================================
 * UIViewController
 * ==========================================
 */

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {

    %orig(animated);

    if (!SC16Enabled())
        return;

    UIViewController *vc = self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            UIWindow *window =
                SC16WindowForView(vc.view);

            if (window &&
                window.rootViewController == vc) {

                SC16Apply(window);
            }
        }
    );
}

- (void)viewDidLayoutSubviews {

    %orig;

    if (!SC16Enabled())
        return;

    UIViewController *vc = self;

    UIWindow *window =
        SC16WindowForView(vc.view);

    if (!window)
        return;

    if (window.rootViewController != vc)
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16Apply(window);
        }
    );
}

%end


/*
 * ==========================================
 * ORIENTATION
 * ==========================================
 */

%ctor {

    @autoreleasepool {

        if (!SC16Enabled())
            return;


        /*
         * Initial.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ApplyAll();
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
                ^(__unused NSNotification *n) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAll();
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
                ^(__unused NSNotification *n) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAll();
                    }
                );
            }];


        /*
         * Xoay màn hình.
         *
         * Đợi geometry của UIWindowScene
         * cập nhật xong rồi mới crop.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:
                [NSOperationQueue mainQueue]
            usingBlock:
                ^(__unused NSNotification *n) {

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)
                        (0.25 *
                         NSEC_PER_SEC)
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAll();
                    }
                );
            }];
    }
}
