#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

/*
 * CROP THỰC TẾ
 *
 * Portrait:
 *   trên 34px
 *   dưới 34px
 *
 * Landscape:
 *   trái 34px
 *   phải 34px
 */
static CGFloat const SC16_CROP = 34.0;

/*
 * DỊCH RIÊNG UI
 *
 * Portrait:
 *   lên 10px
 *
 * Landscape:
 *   sang trái 10px
 *
 * Không dùng giá trị này cho crop.
 */
static CGFloat const SC16_UI_SHIFT = 10.0;

/*
 * Đa nhiệm:
 *
 * 0 = góc vuông.
 */
static CGFloat const SC16_MULTITASK_CORNER = 0.0;

#pragma mark - Enable

static BOOL SC16Enabled(void)
{
    NSString *version =
        UIDevice.currentDevice.systemVersion;

    return [version hasPrefix:@"16."];
}

#pragma mark - Window Filter

static BOOL SC16IsKeyboardWindow(UIWindow *window)
{
    if (!window)
        return YES;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"UITextEffectsWindow"])
        return YES;

    if ([name containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([name containsString:@"Keyboard"])
        return YES;

    if ([name containsString:@"KeyboardWindow"])
        return YES;

    return NO;
}

static BOOL SC16IsStatusBarWindow(UIWindow *window)
{
    if (!window)
        return YES;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"StatusBar"])
        return YES;

    if ([name containsString:@"_UIStatusBar"])
        return YES;

    return NO;
}

static BOOL SC16IsTextEffectsWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"TextEffects"])
        return YES;

    return NO;
}

static BOOL SC16IsAlertWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"Alert"])
        return YES;

    if ([name containsString:@"UIAlert"])
        return YES;

    return NO;
}

static BOOL SC16ShouldSkipWindow(UIWindow *window)
{
    if (!window)
        return YES;

    if (window.hidden)
        return YES;

    if (window.alpha <= 0.0)
        return YES;

    if (SC16IsKeyboardWindow(window))
        return YES;

    if (SC16IsStatusBarWindow(window))
        return YES;

    if (SC16IsTextEffectsWindow(window))
        return YES;

    if (SC16IsAlertWindow(window))
        return YES;

    return NO;
}

#pragma mark - Screen Geometry

static UIScreen *SC16ScreenForWindow(UIWindow *window)
{
    if (!window)
        return UIScreen.mainScreen;

    UIScreen *screen =
        window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    return screen;
}

static BOOL SC16IsLandscapeWindow(UIWindow *window)
{
    UIScreen *screen =
        SC16ScreenForWindow(window);

    if (!screen)
        return NO;

    CGRect bounds =
        screen.bounds;

    return CGRectGetWidth(bounds) >
           CGRectGetHeight(bounds);
}

#pragma mark - Real Crop

static void SC16ApplyCrop(UIWindow *window)
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

    if (width <= 0.0 ||
        height <= 0.0)
    {
        return;
    }

    CGFloat crop =
        SC16_CROP;

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    /*
     * PORTRAIT
     *
     * Cắt trên + dưới.
     */
    if (height > width)
    {
        top = crop;
        bottom = crop;
    }

    /*
     * LANDSCAPE
     *
     * Cắt trái + phải.
     */
    else
    {
        left = crop;
        right = crop;
    }

    CGFloat visibleWidth =
        width - left - right;

    CGFloat visibleHeight =
        height - top - bottom;

    if (visibleWidth <= 0.0 ||
        visibleHeight <= 0.0)
    {
        return;
    }

    /*
     * Chỉ mask layer để crop.
     *
     * KHÔNG transform UIWindow.
     */
    CALayer *layer =
        window.layer;

    layer.mask = nil;

    CGRect visibleRect =
        CGRectMake(
            CGRectGetMinX(bounds) + left,
            CGRectGetMinY(bounds) + top,
            visibleWidth,
            visibleHeight
        );

    CAShapeLayer *mask =
        [CAShapeLayer layer];

    mask.frame =
        bounds;

    CGPathRef path =
        CGPathCreateWithRect(
            visibleRect,
            NULL
        );

    mask.path =
        path;

    CGPathRelease(path);

    layer.mask =
        mask;
}

#pragma mark - UI Shift

/*
 * Dịch ROOT UI, không dịch UIWindow.
 *
 * Vì crop nằm trên window.layer,
 * root view được dịch bên trong vùng crop.
 *
 * Portrait:
 *   Y - 10
 *
 * Landscape:
 *   X - 10
 */
static void SC16ApplyUIShift(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    UIView *rootView =
        window.rootViewController.view;

    if (!rootView)
        return;

    /*
     * Không thay đổi frame/bounds.
     * Chỉ dịch nội dung UI.
     */
    CGAffineTransform transform =
        CGAffineTransformIdentity;

    if (SC16IsLandscapeWindow(window))
    {
        transform =
            CGAffineTransformMakeTranslation(
                -SC16_UI_SHIFT,
                0.0
            );
    }
    else
    {
        transform =
            CGAffineTransformMakeTranslation(
                0.0,
                -SC16_UI_SHIFT
            );
    }

    rootView.transform =
        transform;
}

#pragma mark - Multitasking Detection

static BOOL SC16IsMultitaskingView(UIView *view)
{
    if (!view)
        return NO;

    NSString *name =
        NSStringFromClass(view.class);

    if ([name containsString:@"Switcher"])
        return YES;

    if ([name containsString:@"SBAppSwitcher"])
        return YES;

    if ([name containsString:@"SBFluidSwitcher"])
        return YES;

    if ([name containsString:@"FluidSwitcher"])
        return YES;

    if ([name containsString:@"Multitasking"])
        return YES;

    if ([name containsString:@"AppSwitcher"])
        return YES;

    return NO;
}

#pragma mark - Multitasking Corner

/*
 * Chỉ ép corner của view đa nhiệm.
 *
 * Không áp dụng cho app window bình thường.
 */
static void SC16ApplyMultitaskingCorner(UIView *view)
{
    if (!SC16Enabled())
        return;

    if (!SC16IsMultitaskingView(view))
        return;

    CALayer *layer =
        view.layer;

    if (!layer)
        return;

    layer.cornerRadius =
        SC16_MULTITASK_CORNER;

    /*
     * Đảm bảo cornerRadius = 0
     * thực sự không tạo clipping bo góc.
     */
    if (SC16_MULTITASK_CORNER <= 0.0)
    {
        layer.masksToBounds = NO;
    }
    else
    {
        layer.masksToBounds = YES;
    }
}

#pragma mark - Apply Window

static void SC16ApplyWindow(UIWindow *window)
{
    if (!window)
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    /*
     * Thứ tự quan trọng:
     *
     * 1. Crop window.
     * 2. Dịch root UI.
     *
     * Không transform UIWindow.
     */
    SC16ApplyCrop(window);

    SC16ApplyUIShift(window);
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

#pragma mark - Window Hooks

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
            SC16ApplyWindow(window);
        }
    );
}

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
            if (!window ||
                window.hidden)
            {
                return;
            }

            SC16ApplyWindow(window);
        }
    );
}

%end

#pragma mark - UIView Hooks

/*
 * Hook UIView để bắt view/card của App Switcher.
 *
 * Không sửa geometry của các view khác.
 */
%hook UIView

- (void)didMoveToWindow
{
    %orig;

    if (!SC16Enabled())
        return;

    UIView *view =
        self;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyMultitaskingCorner(view);
        }
    );
}

- (void)layoutSubviews
{
    %orig;

    if (!SC16Enabled())
        return;

    SC16ApplyMultitaskingCorner(self);
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
                SC16ApplyAllScenes();

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.50 *
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
