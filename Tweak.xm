#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

/*
 * Cắt/đẩy theo cạnh dài.
 *
 * Portrait:
 *   trên 34
 *   dưới 34
 *
 * Landscape:
 *   trái 34
 *   phải 34
 */
static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;

/*
 * Dịch UI.
 *
 * Portrait:
 *   +10 = đẩy xuống 10px
 *
 * Landscape:
 *   +10 = đẩy sang phải 10px
 *
 * Giữ nguyên giá trị này là 10.
 */
static CGFloat const SC16_SHIFT = 10.0;

/*
 * Bo góc toàn bộ màn hình.
 */
static CGFloat const SC16_CORNER_RADIUS = 4.0;

#pragma mark - Enable

static BOOL SC16Enabled(void)
{
    NSString *version =
        UIDevice.currentDevice.systemVersion;

    return [version hasPrefix:@"16."];
}

#pragma mark - Window Filter

static BOOL SC16ShouldSkipWindow(UIWindow *window)
{
    if (!window)
        return YES;

    if (window.hidden)
        return YES;

    if (window.alpha <= 0.0)
        return YES;

    NSString *name =
        NSStringFromClass(window.class);

    /*
     * Không đụng keyboard.
     */
    if ([name containsString:@"UITextEffectsWindow"])
        return YES;

    if ([name containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([name containsString:@"Keyboard"])
        return YES;

    if ([name containsString:@"KeyboardWindow"])
        return YES;

    /*
     * Không đụng status bar.
     */
    if ([name containsString:@"StatusBar"])
        return YES;

    if ([name containsString:@"_UIStatusBar"])
        return YES;

    /*
     * Không đụng alert.
     */
    if ([name containsString:@"Alert"])
        return YES;

    if ([name containsString:@"UIAlert"])
        return YES;

    return NO;
}

#pragma mark - Screen Geometry

static BOOL SC16IsLandscapeWindow(UIWindow *window)
{
    if (!window)
        return NO;

    UIScreen *screen =
        window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGRect bounds =
        screen.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    return width > height;
}

#pragma mark - Apply UI Position

static void SC16ApplyPosition(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    CGRect bounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(bounds);

    CGFloat height =
        CGRectGetHeight(bounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    /*
     * Giữ nguyên kích thước window.
     *
     * Chỉ thay đổi origin của bounds
     * để dịch vùng UI.
     */
    if (SC16IsLandscapeWindow(window))
    {
        /*
         * LANDSCAPE
         *
         * Dịch sang phải 10.
         */
        bounds.origin.x =
            SC16_SHIFT;
    }
    else
    {
        /*
         * PORTRAIT
         *
         * Dịch xuống 10.
         */
        bounds.origin.y =
            SC16_SHIFT;
    }

    window.bounds =
        bounds;
}

#pragma mark - Apply Corners

static void SC16ApplyCorners(UIWindow *window)
{
    if (!window)
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    /*
     * Bo nhẹ 4 góc.
     */
    window.layer.cornerRadius =
        SC16_CORNER_RADIUS;

    window.layer.masksToBounds =
        YES;
}

#pragma mark - Apply Window

static void SC16ApplyWindow(UIWindow *window)
{
    if (!window)
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    /*
     * Dịch UI.
     */
    SC16ApplyPosition(window);

    /*
     * Bo 4 góc.
     */
    SC16ApplyCorners(window);
}

#pragma mark - Scene

static void SC16ApplyScene(UIWindowScene *scene)
{
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
    {
        return;
    }

    NSArray<UIWindow *> *windows =
        scene.windows;

    for (UIWindow *window in windows)
    {
        if (!window)
            continue;

        if (window.hidden)
            continue;

        SC16ApplyWindow(window);
    }
}

#pragma mark - All Scenes

static void SC16ApplyAllScenes(void)
{
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    NSSet<UIScene *> *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes)
    {
        if (![scene
              isKindOfClass:[UIWindowScene class]])
        {
            continue;
        }

        SC16ApplyScene(
            (UIWindowScene *)scene
        );
    }
}

#pragma mark - UIWindow Hooks

%hook UIWindow

/*
 * Window mới hiển thị.
 */
- (void)makeKeyAndVisible
{
    %orig;

    if (!SC16Enabled())
        return;

    UIWindow *window =
        self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!window)
                return;

            SC16ApplyWindow(window);
        }
    );
}

/*
 * Window xuất hiện.
 */
- (void)setHidden:(BOOL)hidden
{
    %orig(hidden);

    if (!SC16Enabled())
        return;

    if (hidden)
        return;

    UIWindow *window =
        self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!window || window.hidden)
                return;

            SC16ApplyWindow(window);
        }
    );
}

%end

#pragma mark - Constructor

%ctor
{
    @autoreleasepool
    {
        if (!SC16Enabled())
            return;

        /*
         * Đợi UIKit tạo window/scene.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ApplyAllScenes();

                /*
                 * Apply lại sau layout.
                 */
                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.5 *
                            NSEC_PER_SEC
                        )
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAllScenes();
                    }
                );
            }
        );
    }
}
