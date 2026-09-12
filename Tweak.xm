#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;
static CGFloat const SC16_CORNER_RADIUS = 2.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

/*
 * Chỉ bỏ qua các UIWindow thuộc hệ thống bàn phím/status bar.
 * UIWindow của ứng dụng vẫn được xử lý.
 */
static BOOL SC16IsExcludedWindow(UIWindow *window) {
    if (!window)
        return YES;

    NSString *name = NSStringFromClass(window.class);

    if ([name containsString:@"UITextEffectsWindow"])
        return YES;

    if ([name containsString:@"UIRemoteKeyboardWindow"])
        return YES;

    if ([name containsString:@"Keyboard"])
        return YES;

    if ([name containsString:@"StatusBar"])
        return YES;

    if ([name containsString:@"_UIStatusBar"])
        return YES;

    return NO;
}

/*
 * Lấy kích thước vùng hiển thị thực tế của window.
 *
 * QUAN TRỌNG:
 * Không dùng UIApplication.windows.
 * Không thay đổi window.bounds.
 * Không thay đổi window.frame.
 */
static CGRect SC16ScreenRect(UIWindow *window) {
    if (!window)
        return CGRectZero;

    UIScreen *screen = window.screen;

    if (!screen)
        screen = UIScreen.mainScreen;

    CGRect rect = screen.bounds;

    /*
     * screen.bounds có thể đổi khi rotation.
     */
    if (rect.size.width <= 0.0 ||
        rect.size.height <= 0.0) {
        return CGRectZero;
    }

    return rect;
}

/*
 * Xác định hướng hiện tại.
 *
 * Không dựa vào UIDeviceOrientation để tính kích thước.
 * screen.bounds đã phản ánh orientation hiện tại.
 */
static BOOL SC16IsLandscape(UIWindow *window) {
    CGRect screenRect = SC16ScreenRect(window);

    if (CGRectIsEmpty(screenRect))
        return NO;

    return CGRectGetWidth(screenRect) >
           CGRectGetHeight(screenRect);
}

/*
 * Reset trạng thái trước khi apply.
 *
 * Điều này rất quan trọng khi rotation:
 * tránh transform/mask của portrait bị giữ lại
 * rồi áp tiếp lên landscape.
 */
static void SC16ResetWindowVisualState(UIWindow *window) {
    if (!window)
        return;

    window.layer.transform = CATransform3DIdentity;
    window.layer.mask = nil;
    window.layer.cornerRadius = 0.0;
    window.layer.masksToBounds = NO;
}

/*
 * Crop + scale thật.
 *
 * Portrait:
 *   trên 34px
 *   dưới 34px
 *
 * Landscape:
 *   giữ cùng ý nghĩa "hai cạnh an toàn" của màn hình:
 *   cạnh trái/phải tương ứng vùng notch/home khi xoay.
 *
 * Window geometry KHÔNG bị thay đổi.
 * UIKit vẫn layout theo màn hình gốc.
 *
 * Chỉ visual layer được scale/crop.
 */
static void SC16ApplyVisualCrop(UIWindow *window) {
    if (!SC16Enabled() ||
        !window ||
        SC16IsExcludedWindow(window) ||
        window.hidden ||
        window.alpha <= 0.0) {
        return;
    }

    CGRect screenRect = SC16ScreenRect(window);

    if (CGRectIsEmpty(screenRect))
        return;

    CGFloat screenWidth = CGRectGetWidth(screenRect);
    CGFloat screenHeight = CGRectGetHeight(screenRect);

    /*
     * Nếu landscape:
     *
     * notch và vùng home indicator nằm ở hai cạnh
     * trái/phải khi thiết bị xoay ngang.
     *
     * Vì vậy crop 34px ở hai cạnh ngang.
     */
    BOOL landscape = SC16IsLandscape(window);

    CGFloat cropA;
    CGFloat cropB;

    if (landscape) {
        cropA = SC16_TOP_CROP;
        cropB = SC16_BOTTOM_CROP;
    } else {
        cropA = SC16_TOP_CROP;
        cropB = SC16_BOTTOM_CROP;
    }

    CGFloat availableWidth;
    CGFloat availableHeight;

    if (landscape) {
        availableWidth = screenWidth - cropA - cropB;
        availableHeight = screenHeight;
    } else {
        availableWidth = screenWidth;
        availableHeight = screenHeight - cropA - cropB;
    }

    if (availableWidth <= 0.0 ||
        availableHeight <= 0.0) {
        return;
    }

    /*
     * Scale đồng đều X/Y.
     *
     * Không scale X riêng/Y riêng
     * => không méo hình.
     *
     * Chọn scale nhỏ nhất để toàn bộ nội dung
     * nằm trong vùng crop.
     */
    CGFloat scaleX = availableWidth / screenWidth;
    CGFloat scaleY = availableHeight / screenHeight;

    CGFloat scale = MIN(scaleX, scaleY);

    if (scale <= 0.0)
        return;

    /*
     * Reset trước khi tính transform.
     */
    window.layer.transform = CATransform3DIdentity;

    /*
     * Scale quanh tâm window.
     */
    CATransform3D transform =
        CATransform3DMakeScale(scale, scale, 1.0);

    window.layer.transform = transform;

    /*
     * Sau khi scale, căn chính giữa màn hình.
     *
     * Window.frame vẫn giữ nguyên.
     * Chỉ layer.presentation được nhìn thấy
     * trong vùng crop.
     */
    CGPoint center = window.layer.position;

    /*
     * Vì transform scale quanh anchorPoint,
     * layer vẫn nằm đúng tâm.
     */
    window.layer.position = center;

    /*
     * Tạo mask để phần ngoài vùng crop
     * thực sự không được render.
     *
     * Không dùng bounds mới.
     */
    CALayer *mask = [CALayer layer];

    mask.frame = window.bounds;

    /*
     * Mặc định mask toàn màn hình.
     * Sau đó cắt vùng không mong muốn.
     */
    CAShapeLayer *shape = [CAShapeLayer layer];

    UIBezierPath *path =
        [UIBezierPath bezierPathWithRect:window.bounds];

    /*
     * Vùng bị loại khỏi mask.
     */
    UIBezierPath *cutPath = nil;

    if (landscape) {

        CGRect visibleRect =
            CGRectMake(
                cropA,
                0.0,
                screenWidth - cropA - cropB,
                screenHeight
            );

        /*
         * Mask chỉ giữ vùng visibleRect.
         */
        cutPath =
            [UIBezierPath bezierPathWithRect:visibleRect];

    } else {

        CGRect visibleRect =
            CGRectMake(
                0.0,
                cropA,
                screenWidth,
                screenHeight - cropA - cropB
            );

        cutPath =
            [UIBezierPath bezierPathWithRect:visibleRect];
    }

    shape.path = cutPath.CGPath;
    shape.fillColor = UIColor.blackColor.CGColor;

    mask.frame = window.bounds;

    /*
     * Dùng CAShapeLayer trực tiếp làm mask.
     */
    window.layer.mask = shape;

    /*
     * Bo rất nhẹ 2px.
     */
    window.layer.cornerRadius = SC16_CORNER_RADIUS;
    window.layer.masksToBounds = YES;
}

/*
 * Apply visual state.
 */
static void SC16ApplyWindow(UIWindow *window) {
    if (!window)
        return;

    if (SC16IsExcludedWindow(window))
        return;

    if (window.hidden)
        return;

    SC16ApplyVisualCrop(window);
}

/*
 * Apply tất cả window của một scene.
 */
static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled() || !scene)
        return;

    if (scene.activationState ==
        UISceneActivationStateUnattached) {
        return;
    }

    NSArray<UIWindow *> *windows = scene.windows;

    for (UIWindow *window in windows) {

        if (!window)
            continue;

        if (window.hidden)
            continue;

        SC16ApplyWindow(window);
    }
}

/*
 * Apply toàn bộ connected scenes.
 */
static void SC16ApplyAllScenes(void) {
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

        SC16ApplyScene(windowScene);
    }
}

/*
 * Reapply sau khi UIKit hoàn tất rotation/layout.
 *
 * Không gọi setFrame/bounds ở đây.
 * Chỉ cập nhật visual layer.
 */
static void SC16ScheduleApply(void) {

    if (!SC16Enabled())
        return;

    dispatch_async(dispatch_get_main_queue(), ^{

        SC16ApplyAllScenes();

        /*
         * Một tick tiếp theo để bắt trường hợp
         * UIKit vừa thay đổi screen.bounds sau rotation.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ApplyAllScenes();
            }
        );
    });
}


%hook UIWindow

/*
 * Window xuất hiện.
 */
- (void)makeKeyAndVisible {

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
 * Window được hiện lại.
 */
- (void)setHidden:(BOOL)hidden {

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
 * KHÔNG hook setFrame.
 *
 * Đây là nguyên nhân quan trọng gây:
 * - layout loop
 * - lag
 * - giật
 * - Safe Mode
 * - rotation lỗi
 *
 * UIKit được phép tự quản lý frame.
 */

%end


%ctor {

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
            usingBlock:^(__unused NSNotification *notification) {

                SC16ScheduleApply();
            }];


        /*
         * Scene activate.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {

                    SC16ScheduleApply();
                }
            }];


        /*
         * Scene foreground.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneWillEnterForegroundNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {

                    SC16ScheduleApply();
                }
            }];


        /*
         * Rotation.
         *
         * Không dùng UIWindowSceneDidUpdateNotification
         * vì symbol này không tồn tại trong SDK đang build.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                /*
                 * Để UIKit cập nhật screen.bounds trước.
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
            }];
    }
}
