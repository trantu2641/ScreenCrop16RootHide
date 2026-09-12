#import <UIKit/UIKit.h>

static CGFloat const SC16_CROP = 34.0;

static BOOL SC16Enabled(void)
{
    return [UIDevice.currentDevice.systemVersion hasPrefix:@"16."];
}

static BOOL SC16ValidWindow(UIWindow *window)
{
    if (!window)
        return NO;

    if (window.hidden)
        return NO;

    if (window.alpha <= 0.0)
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    /*
     * Bỏ qua keyboard / text effects.
     */
    if ([name containsString:@"Keyboard"])
        return NO;

    if ([name containsString:@"TextEffects"])
        return NO;

    /*
     * Bỏ qua status bar window.
     */
    if ([name containsString:@"StatusBar"])
        return NO;

    return YES;
}

static void SC16ApplyViewport(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (!SC16ValidWindow(window))
        return;

    UIViewController *root =
        window.rootViewController;

    if (!root)
        return;

    UIView *view =
        root.view;

    if (!view)
        return;

    CGRect windowBounds =
        window.bounds;

    CGFloat width =
        CGRectGetWidth(windowBounds);

    CGFloat height =
        CGRectGetHeight(windowBounds);

    if (width <= 0.0 || height <= 0.0)
        return;

    BOOL landscape =
        width > height;

    UIEdgeInsets inset = UIEdgeInsetsZero;

    /*
     * DỌC
     *
     * ┌─────────────────┐
     * │      34         │
     * ├─────────────────┤
     * │                 │
     * │      UI         │
     * │                 │
     * ├─────────────────┤
     * │      34         │
     * └─────────────────┘
     */
    if (!landscape)
    {
        inset.top =
            SC16_CROP;

        inset.bottom =
            SC16_CROP;
    }
    /*
     * NGANG
     *
     * ┌────┬─────────────┬────┐
     * │ 34 │     UI      │ 34 │
     * └────┴─────────────┴────┘
     */
    else
    {
        inset.left =
            SC16_CROP;

        inset.right =
            SC16_CROP;
    }

    CGRect newFrame =
        UIEdgeInsetsInsetRect(
            windowBounds,
            inset
        );

    if (newFrame.size.width <= 0.0 ||
        newFrame.size.height <= 0.0)
    {
        return;
    }

    /*
     * QUAN TRỌNG:
     *
     * Không transform.
     * Không mask.
     * Không thay UIWindow.
     *
     * Chỉ thay vùng viewport của root view.
     */
    view.frame =
        newFrame;

    /*
     * Cho UIKit layout lại UI trong
     * vùng mới.
     */
    [view setNeedsLayout];
    [view layoutIfNeeded];
}

static void SC16ApplyAll(void)
{
    if (!SC16Enabled())
        return;

    UIApplication *app =
        UIApplication.sharedApplication;

    for (UIScene *scene in app.connectedScenes)
    {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *ws =
            (UIWindowScene *)scene;

        if (ws.activationState ==
            UISceneActivationStateUnattached)
        {
            continue;
        }

        for (UIWindow *window in ws.windows)
        {
            SC16ApplyViewport(window);
        }
    }
}

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
            SC16ApplyViewport(window);
        }
    );
}

%end

%ctor
{
    @autoreleasepool
    {
        if (!SC16Enabled())
            return;

        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ApplyAll();

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.3 *
                            NSEC_PER_SEC
                        )
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        SC16ApplyAll();
                    }
                );
            }
        );
    }
}
