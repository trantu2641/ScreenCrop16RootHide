#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

/*
 * Số pixel cần cắt ở mỗi đầu.
 *
 * Đây là PIXEL vật lý, sau đó được đổi sang point
 * theo nativeScale của màn hình.
 */
static CGFloat const SC16_CROP_PIXELS = 34.0;

/*
 * Góc UI đa nhiệm.
 *
 * Không áp dụng cho app window bình thường.
 */
static CGFloat const SC16_MULTITASK_CORNER = 0.0;

#pragma mark - Enable

static BOOL SC16Enabled(void)
{
    NSString *version =
        UIDevice.currentDevice.systemVersion;

    /*
     * Chỉ chạy iOS 16.x
     */
    if (![version hasPrefix:@"16."])
        return NO;

    return YES;
}

#pragma mark - Window Detection

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

static BOOL SC16IsAlertWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"Alert"])
        return YES;

    if ([name containsString:@"TextEffects"])
        return YES;

    return NO;
}

/*
 * Những window này không được crop.
 *
 * Quan trọng:
 * Không dùng window.class == một class private cụ thể.
 * Chỉ loại keyboard/status/alert để tránh phá UIKit.
 */
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

    if (SC16IsAlertWindow(window))
        return YES;

    return NO;
}

#pragma mark - Screen Geometry

/*
 * Lấy kích thước thực tế của screen theo orientation.
 *
 * Không dùng UIApplication.windows.
 * Không dùng transform để suy luận orientation.
 */
static CGRect SC16ScreenBounds(UIWindow *window)
{
    if (!window)
        return CGRectZero;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    return screen.bounds;
}

/*
 * Xác định landscape dựa trên screen bounds.
 *
 * Ví dụ:
 *
 * Portrait:
 * 414 x 896
 *
 * Landscape:
 * 896 x 414
 *
 * Vì vậy cạnh dài luôn là:
 *
 * Portrait  -> height
 * Landscape -> width
 */
static BOOL SC16IsLandscapeWindow(UIWindow *window)
{
    CGRect screenBounds =
        SC16ScreenBounds(window);

    CGFloat width =
        CGRectGetWidth(screenBounds);

    CGFloat height =
        CGRectGetHeight(screenBounds);

    return width > height;
}

/*
 * 34 physical pixels -> UIKit points.
 *
 * Ví dụ màn hình @3x:
 *
 * 34 px / 3 = 11.33 pt
 *
 * Như vậy không vô tình cắt 102 px vật lý.
 */
static CGFloat SC16CropPointsForWindow(UIWindow *window)
{
    if (!window)
        return 0.0;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGFloat scale =
        screen.nativeScale;

    if (scale <= 0.0)
        scale = screen.scale;

    if (scale <= 0.0)
        scale = 1.0;

    return SC16_CROP_PIXELS / scale;
}

#pragma mark - Crop Mask

/*
 * Tạo mask để CẮT THỰC SỰ nội dung.
 *
 * Không:
 *
 * - overlay màu đen
 * - scale
 * - transform
 * - thay đổi frame
 * - thay đổi center
 *
 * Nội dung bên ngoài path sẽ không được layer render.
 */
static void SC16ApplyCropMask(UIWindow *window)
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

    CGFloat crop =
        SC16CropPointsForWindow(window);

    if (crop <= 0.0)
        return;

    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat top = 0.0;
    CGFloat bottom = 0.0;

    /*
     * LUÔN CẮT CẠNH DÀI.
     *
     * Portrait:
     *
     *       1284
     *   ┌──────────┐
     *   │          │
     *   │   2778   │
     *   │          │
     *   └──────────┘
     *
     * Cắt:
     * trên 34px
     * dưới 34px
     *
     *
     * Landscape:
     *
     *        2778
     *   ┌────────────────┐
     *   │                │
     *   │      1248      │
     *   │                │
     *   └────────────────┘
     *
     * Cắt:
     * trái 34px
     * phải 34px
     *
     * Không cắt theo cạnh 1248.
     */
    if (SC16IsLandscapeWindow(window))
    {
        left = crop;
        right = crop;
    }
    else
    {
        top = crop;
        bottom = crop;
    }

    CGFloat visibleWidth =
        width - left - right;

    CGFloat visibleHeight =
        height - top - bottom;

    if (visibleWidth <= 0.0 ||
        visibleHeight <= 0.0)
        return;

    /*
     * Xóa mask cũ trước khi tạo mask mới.
     *
     * Điều này rất quan trọng khi rotation:
     * mask cũ của portrait không được giữ lại
     * khi window chuyển sang landscape.
     */
    window.layer.mask = nil;

    /*
     * Giữ nguyên geometry của window.
     */
    window.transform =
        CGAffineTransformIdentity;

    /*
     * Vùng thực sự được render.
     */
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

    /*
     * Clipping thực sự.
     */
    window.layer.mask =
        mask;
}

#pragma mark - Multitasking

/*
 * Chỉ nhận diện những window có dấu hiệu thuộc
 * SpringBoard / App Switcher.
 *
 * Không dùng hàm SC16IsSpringBoard() riêng,
 * tránh unused-function và cũng không cần ép
 * tweak chỉ chạy trong SpringBoard.
 */
static BOOL SC16IsMultitaskingWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *name =
        NSStringFromClass(window.class);

    if ([name containsString:@"Switcher"])
        return YES;

    if ([name containsString:@"SwitcherWindow"])
        return YES;

    if ([name containsString:@"Multitasking"])
        return YES;

    if ([name containsString:@"SBAppSwitcher"])
        return YES;

    if ([name containsString:@"SBFluidSwitcher"])
        return YES;

    return NO;
}

/*
 * UI đa nhiệm phải vuông.
 *
 * cornerRadius = 0
 *
 * Không bo app window.
 */
static void SC16ApplyMultitaskingCorner(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16IsMultitaskingWindow(window))
        return;

    window.layer.cornerRadius =
        SC16_MULTITASK_CORNER;

    window.layer.masksToBounds =
        YES;
}

#pragma mark - Window Apply

static void SC16ApplyWindow(UIWindow *window)
{
    if (!window)
        return;

    if (SC16ShouldSkipWindow(window))
        return;

    /*
     * Crop thật.
     */
    SC16ApplyCropMask(window);

    /*
     * Chỉ tác động UI đa nhiệm.
     */
    SC16ApplyMultitaskingCorner(window);
}

#pragma mark - Scene Apply

static void SC16ApplyScene(UIWindowScene *scene)
{
    if (!SC16Enabled())
        return;

    if (!scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached)
        return;

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

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        SC16ApplyScene(windowScene);
    }
}

#pragma mark - Delayed Apply

static void SC16ScheduleApply(void)
{
    if (!SC16Enabled())
        return;

    /*
     * Đợi UIKit hoàn tất layout/rotation.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();

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
        }
    );
}

#pragma mark - Observers

static void SC16InstallObservers(void)
{
    NSNotificationCenter *center =
        [NSNotificationCenter defaultCenter];

    /*
     * App active.
     */
    [center addObserverForName:
        UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(__unused NSNotification *notification)
        {
            SC16ScheduleApply();
        }];

    /*
     * Scene active.
     */
    [center addObserverForName:
        UISceneDidActivateNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification)
        {
            UIScene *scene =
                notification.object;

            if (![scene
                  isKindOfClass:[UIWindowScene class]])
            {
                return;
            }

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            );
        }];

    /*
     * Scene foreground.
     */
    [center addObserverForName:
        UISceneWillEnterForegroundNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(NSNotification *notification)
        {
            UIScene *scene =
                notification.object;

            if (![scene
                  isKindOfClass:[UIWindowScene class]])
            {
                return;
            }

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            );
        }];

    /*
     * Rotation.
     *
     * Không dùng UIWindowSceneDidUpdateNotification.
     */
    [center addObserverForName:
        UIDeviceOrientationDidChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:
        ^(__unused NSNotification *notification)
        {
            /*
             * Cho UIKit cập nhật bounds trước.
             */
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(0.20 *
                              NSEC_PER_SEC)
                ),
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();

                    /*
                     * Một lần nữa để xử lý trường hợp
                     * window resize sau notification.
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
                }
            );
        }];
}

#pragma mark - UIWindow Hooks

%hook UIWindow

/*
 * Window mới xuất hiện.
 */
- (void)makeKeyAndVisible
{
    %orig;

    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyWindow(self);
        }
    );
}

/*
 * Window được show.
 */
- (void)setHidden:(BOOL)hidden
{
    %orig(hidden);

    if (!SC16Enabled())
        return;

    if (hidden)
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyWindow(self);
        }
    );
}

/*
 * Window resize / rotation.
 *
 * Không crop trực tiếp trong setFrame để tránh
 * vòng lặp layout.
 */
- (void)setFrame:(CGRect)frame
{
    %orig(frame);

    if (!SC16Enabled())
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!self.hidden)
            {
                SC16ApplyWindow(self);
            }
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
         * UIKit phải khởi tạo trước.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16InstallObservers();

                SC16ApplyAllScenes();

                /*
                 * Apply thêm một lần sau khi
                 * toàn bộ window ổn định.
                 */
                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(0.25 *
                                  NSEC_PER_SEC)
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
