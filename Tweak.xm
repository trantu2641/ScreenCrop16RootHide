#import <UIKit/UIKit.h>

#pragma mark - Configuration

static CGFloat const SC16_INSET = 34.0;


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
     * Keyboard
     */
    if ([name containsString:@"UITextEffectsWindow"])
        return YES;

    if ([name containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([name containsString:@"KeyboardWindow"])
        return YES;

    if ([name containsString:@"Keyboard"])
        return YES;

    /*
     * Status bar
     */
    if ([name containsString:@"StatusBar"])
        return YES;

    if ([name containsString:@"_UIStatusBar"])
        return YES;

    return NO;
}


#pragma mark - Apply Insets

static void SC16ApplyInsets(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    UIViewController *root =
        window.rootViewController;

    if (!root)
        return;

    /*
     * Không xử lý khi root view chưa có kích thước.
     */
    UIView *view =
        root.view;

    if (!view)
        return;

    if (view.bounds.size.width <= 0.0 ||
        view.bounds.size.height <= 0.0)
    {
        return;
    }

    /*
     * Xác định orientation bằng kích thước
     * thực tế của root view.
     */
    BOOL landscape =
        view.bounds.size.width >
        view.bounds.size.height;

    /*
     * Lấy safe-area hiện tại.
     *
     * additionalSafeAreaInsets là phần INSET
     * cộng thêm vào safe area của UIKit.
     */
    UIEdgeInsets inset =
        UIEdgeInsetsZero;

    if (landscape)
    {
        /*
         * NGANG
         *
         * Trái 34
         * Phải 34
         */
        inset.left =
            SC16_INSET;

        inset.right =
            SC16_INSET;
    }
    else
    {
        /*
         * DỌC
         *
         * Trên 34
         * Dưới 34
         */
        inset.top =
            SC16_INSET;

        inset.bottom =
            SC16_INSET;
    }

    /*
     * Không transform.
     * Không đổi frame.
     * Không đổi bounds.
     *
     * UIKit sẽ tự layout những view sử dụng
     * safeAreaInsets vào vùng mới.
     */
    root.additionalSafeAreaInsets =
        inset;

    /*
     * Yêu cầu UIKit cập nhật layout.
     */
    [root.view setNeedsLayout];

    [root.view layoutIfNeeded];
}


#pragma mark - Apply All Scenes

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

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
        {
            continue;
        }

        NSArray<UIWindow *> *windows =
            windowScene.windows;

        for (UIWindow *window in windows)
        {
            SC16ApplyInsets(window);
        }
    }
}


#pragma mark - UIWindow

%hook UIWindow

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
            SC16ApplyInsets(window);
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

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                /*
                 * Lần đầu.
                 */
                SC16ApplyAllScenes();

                /*
                 * Apply lại sau khi UIKit hoàn tất
                 * việc tạo/layout window.
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
