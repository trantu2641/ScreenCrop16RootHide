#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Configuration

static CGFloat const SC16_CROP = 34.0;
static CGFloat const SC16_MULTITASK_RADIUS = 2.0;

#pragma mark - Helpers

static BOOL SC16Enabled(void)
{
    /*
     * Không giới hạn riêng 16.4 nữa.
     * Tweak hoạt động trên iOS 16.x.
     */
    NSString *version = UIDevice.currentDevice.systemVersion;

    if (![version hasPrefix:@"16."])
        return NO;

    return YES;
}

static BOOL SC16IsKeyboardWindow(UIWindow *window)
{
    if (!window)
        return YES;

    NSString *className = NSStringFromClass(window.class);

    if ([className containsString:@"UITextEffectsWindow"])
        return YES;

    if ([className containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([className containsString:@"Keyboard"])
        return YES;

    return NO;
}

static BOOL SC16IsStatusBarWindow(UIWindow *window)
{
    if (!window)
        return YES;

    NSString *className = NSStringFromClass(window.class);

    if ([className containsString:@"StatusBar"])
        return YES;

    if ([className containsString:@"_UIStatusBar"])
        return YES;

    return NO;
}

static BOOL SC16ShouldIgnoreWindow(UIWindow *window)
{
    if (!window)
        return YES;

    if (window.hidden)
        return YES;

    if (window.alpha <= 0.0)
        return YES;

    /*
     * Không đụng keyboard.
     */
    if (SC16IsKeyboardWindow(window))
        return YES;

    /*
     * Không đụng trực tiếp status bar window.
     */
    if (SC16IsStatusBarWindow(window))
        return YES;

    return NO;
}

#pragma mark - Crop

static void SC16RemoveCrop(UIWindow *window)
{
    if (!window)
        return;

    window.layer.mask = nil;
    window.layer.cornerRadius = 0.0;
    window.layer.masksToBounds = NO;

    /*
     * Tuyệt đối không thay đổi transform.
     */
    window.transform = CGAffineTransformIdentity;
}

static void SC16ApplyRealCrop(UIWindow *window)
{
    if (!SC16Enabled())
        return;

    if (SC16ShouldIgnoreWindow(window))
        return;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGRect screenBounds = screen.bounds;

    CGFloat screenWidth = CGRectGetWidth(screenBounds);
    CGFloat screenHeight = CGRectGetHeight(screenBounds);

    if (screenWidth <= 0.0 || screenHeight <= 0.0)
        return;

    CGFloat windowWidth = CGRectGetWidth(window.bounds);
    CGFloat windowHeight = CGRectGetHeight(window.bounds);

    if (windowWidth <= 0.0 || windowHeight <= 0.0)
        return;

    /*
     * QUAN TRỌNG:
     *
     * Không sửa window.bounds.
     * Không sửa frame.
     * Không scale.
     *
     * Chỉ clip phần render bằng layer mask.
     */

    window.transform = CGAffineTransformIdentity;

    BOOL landscape =
        windowWidth > windowHeight;

    CGFloat leftCrop = 0.0;
    CGFloat rightCrop = 0.0;
    CGFloat topCrop = 0.0;
    CGFloat bottomCrop = 0.0;

    if (!landscape) {

        /*
         * PORTRAIT
         *
         * 1284 x 2778
         *
         * Cắt:
         * trên 34
         * dưới 34
         *
         * Giữ nguyên toàn bộ chiều ngang.
         */
        topCrop = SC16_CROP;
        bottomCrop = SC16_CROP;

    } else {

        /*
         * LANDSCAPE
         *
         * 2778 x 1284
         *
         * Không cắt chiều 1248/1284.
         *
         * Chuyển vùng crop sang hai đầu
         * của cạnh dài 2778.
         *
         * => trái 34
         * => phải 34
         *
         * Nhờ vậy Control Centre / notification
         * ở cạnh ngắn không bị cắt.
         */
        leftCrop = SC16_CROP;
        rightCrop = SC16_CROP;
    }

    CGFloat visibleWidth =
        windowWidth - leftCrop - rightCrop;

    CGFloat visibleHeight =
        windowHeight - topCrop - bottomCrop;

    if (visibleWidth <= 0.0 || visibleHeight <= 0.0)
        return;

    /*
     * CAShapeLayer dùng làm CLIP MASK.
     *
     * Đây không phải overlay màu đen.
     * Pixel nằm ngoài vùng này thực sự không được
     * render ra UIWindow.
     */
    CAShapeLayer *mask = [CAShapeLayer layer];

    CGRect maskRect = CGRectMake(
        leftCrop,
        topCrop,
        visibleWidth,
        visibleHeight
    );

    mask.frame = window.bounds;

    CGPathRef path =
        CGPathCreateWithRect(maskRect, NULL);

    mask.path = path;

    CGPathRelease(path);

    mask.fillRule = kCAFillRuleNonZero;

    window.layer.mask = mask;
}

#pragma mark - Multitasking corner

static BOOL SC16LooksLikeMultitaskingWindow(UIWindow *window)
{
    if (!window)
        return NO;

    NSString *className =
        NSStringFromClass(window.class);

    /*
     * Chỉ dùng để nhận diện các container
     * thường xuất hiện trong UI đa nhiệm.
     *
     * Không ép toàn bộ UIWindow.cornerRadius.
     */
    if ([className containsString:@"SB"])
        return YES;

    if ([className containsString:@"Switcher"])
        return YES;

    if ([className containsString:@"Multitasking"])
        return YES;

    if ([className containsString:@"Card"])
        return YES;

    return NO;
}

static void SC16ApplyMultitaskCorner(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16LooksLikeMultitaskingWindow(window))
        return;

    /*
     * Giữ góc gần vuông như bản đầu:
     * 2.0 px.
     */
    window.layer.cornerRadius =
        SC16_MULTITASK_RADIUS;

    window.layer.masksToBounds = YES;
}

#pragma mark - Window

static void SC16ApplyWindow(UIWindow *window)
{
    if (!window)
        return;

    if (!SC16Enabled())
        return;

    if (SC16ShouldIgnoreWindow(window))
        return;

    /*
     * Crop thật bằng mask.
     */
    SC16ApplyRealCrop(window);

    /*
     * Góc multitasking gần vuông.
     *
     * Không áp dụng corner cho toàn bộ app window,
     * tránh làm app bị bo góc ngoài ý muốn.
     */
    SC16ApplyMultitaskCorner(window);
}

#pragma mark - Scene

static void SC16ApplyScene(UIWindowScene *scene)
{
    if (!scene)
        return;

    if (!SC16Enabled())
        return;

    NSArray<UIWindow *> *windows = scene.windows;

    for (UIWindow *window in windows) {

        if (!window)
            continue;

        if (window.hidden)
            continue;

        SC16ApplyWindow(window);
    }
}

static void SC16ApplyAllScenes(void)
{
    if (!SC16Enabled())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    NSSet<UIScene *> *scenes =
        application.connectedScenes;

    for (UIScene *scene in scenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
            continue;

        SC16ApplyScene(windowScene);
    }
}

#pragma mark - Rotation

static void SC16ReapplyAfterRotation(void)
{
    if (!SC16Enabled())
        return;

    /*
     * Không sửa bounds/frame trong lúc UIKit đang
     * transition rotation.
     *
     * Chờ rotation hoàn tất rồi thay mask.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAllScenes();

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    SC16ApplyAllScenes();
                }
            );
        }
    );
}

#pragma mark - UIWindow Hook

%hook UIWindow

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

- (void)setFrame:(CGRect)frame
{
    %orig(frame);

    if (!SC16Enabled())
        return;

    /*
     * Không thay đổi frame.
     * Chỉ re-apply mask sau layout.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!self.hidden)
                SC16ApplyWindow(self);
        }
    );
}

- (void)setBounds:(CGRect)bounds
{
    %orig(bounds);

    if (!SC16Enabled())
        return;

    /*
     * Rotation / UIKit layout có thể thay bounds.
     *
     * Không can thiệp vào bounds.
     * Chỉ cập nhật lại mask theo kích thước mới.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!self.hidden)
                SC16ApplyWindow(self);
        }
    );
}

%end

#pragma mark - Constructor

%ctor
{
    @autoreleasepool {

        if (!SC16Enabled())
            return;

        /*
         * Initial apply.
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
            queue:[NSOperationQueue mainQueue]
            usingBlock:
            ^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if (![scene
                        isKindOfClass:[UIWindowScene class]])
                    return;

                SC16ApplyScene(
                    (UIWindowScene *)scene
                );
            }];

        /*
         * Scene foreground.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneWillEnterForegroundNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:
            ^(NSNotification *notification) {

                UIScene *scene =
                    notification.object;

                if (![scene
                        isKindOfClass:[UIWindowScene class]])
                    return;

                SC16ApplyScene(
                    (UIWindowScene *)scene
                );
            }];

        /*
         * Rotation.
         *
         * Không dùng:
         * UIWindowSceneDidUpdateNotification
         *
         * vì SDK iOS 16.5 không có symbol này.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:
            ^(__unused NSNotification *notification) {

                SC16ReapplyAfterRotation();
            }];
    }
}
