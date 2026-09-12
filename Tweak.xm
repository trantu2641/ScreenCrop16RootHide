#import <UIKit/UIKit.h>

static CGFloat const SC16_CROP_TOP = 34.0;
static CGFloat const SC16_CROP_BOTTOM = 34.0;

#pragma mark - Helpers

static BOOL SC16IsSupportedOS(void) {
    NSOperatingSystemVersion v = UIDevice.currentDevice.systemVersion.length
        ? NSOperatingSystemVersion{
            UIDevice.currentDevice.systemVersion.floatValue >= 16.0 ? 16 : 0,
            0,
            0
        }
        : NSOperatingSystemVersion{0, 0, 0};

    return v.majorVersion == 16;
}

static UIWindowScene *SC16WindowSceneForWindow(UIWindow *window) {
    if (!window)
        return nil;

    if (@available(iOS 13.0, *)) {
        return window.windowScene;
    }

    return nil;
}

static BOOL SC16IsUsableWindow(UIWindow *window) {
    if (!window)
        return NO;

    if (window.hidden)
        return NO;

    if (window.alpha <= 0.0)
        return NO;

    UIWindowScene *scene = SC16WindowSceneForWindow(window);

    if (!scene)
        return NO;

    if (@available(iOS 13.0, *)) {
        UISceneActivationState state = scene.activationState;

        if (state == UISceneActivationStateUnattached ||
            state == UISceneActivationStateBackground) {
            return NO;
        }
    }

    return YES;
}

#pragma mark - Crop container

@interface SC16CropView : UIView
@property(nonatomic, assign) UIEdgeInsets cropInsets;
@end

@implementation SC16CropView

- (void)layoutSubviews {
    [super layoutSubviews];

    /*
     * Container chỉ làm nhiệm vụ clip.
     * Không scale theo từng trục nên không làm méo hình.
     */

    self.clipsToBounds = YES;

    UIView *content = nil;

    for (UIView *subview in self.subviews) {
        if (subview != self)
            content = subview;
    }

    if (!content)
        return;

    UIEdgeInsets insets = self.cropInsets;

    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);

    CGFloat contentWidth = w - insets.left - insets.right;
    CGFloat contentHeight = h - insets.top - insets.bottom;

    if (contentWidth <= 0 || contentHeight <= 0)
        return;

    /*
     * Scale đồng đều.
     *
     * Tỉ lệ scale giống nhau cho X/Y.
     * Không kéo giãn riêng chiều ngang hoặc dọc.
     */

    CGFloat originalWidth = CGRectGetWidth(content.bounds);
    CGFloat originalHeight = CGRectGetHeight(content.bounds);

    if (originalWidth <= 0 || originalHeight <= 0)
        return;

    CGFloat scaleX = contentWidth / originalWidth;
    CGFloat scaleY = contentHeight / originalHeight;

    CGFloat scale = MIN(scaleX, scaleY);

    if (!isfinite(scale) || scale <= 0)
        scale = 1.0;

    /*
     * Không cho layout thay đổi liên tục.
     */

    content.transform = CGAffineTransformMakeScale(scale, scale);

    CGFloat scaledWidth = originalWidth * scale;
    CGFloat scaledHeight = originalHeight * scale;

    content.center = CGPointMake(
        insets.left + contentWidth / 2.0,
        insets.top + contentHeight / 2.0
    );

    /*
     * Giữ nội dung nằm chính giữa vùng hiển thị.
     */
    CGRect frame = content.frame;

    frame.size.width = scaledWidth;
    frame.size.height = scaledHeight;

    frame.origin.x =
        insets.left + (contentWidth - scaledWidth) / 2.0;

    frame.origin.y =
        insets.top + (contentHeight - scaledHeight) / 2.0;

    content.frame = frame;
}

@end

#pragma mark - State

static NSMapTable<UIWindow *, SC16CropView *> *SC16Containers;

static void SC16InitState(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        SC16Containers =
            [NSMapTable weakToStrongObjectsMapTable];
    });
}

static UIEdgeInsets SC16InsetsForWindow(UIWindow *window) {
    if (!window)
        return UIEdgeInsetsZero;

    UIWindowScene *scene = window.windowScene;

    if (!scene)
        return UIEdgeInsetsZero;

    /*
     * Crop theo kích thước vật lý hiện tại.
     *
     * Portrait:
     *      top    = 34
     *      bottom = 34
     *
     * Landscape:
     *      vẫn loại vùng tương ứng ở hai cạnh
     *      theo hướng màn hình hiện tại.
     */

    UIInterfaceOrientation orientation =
        scene.interfaceOrientation;

    if (orientation == UIInterfaceOrientationLandscapeLeft ||
        orientation == UIInterfaceOrientationLandscapeRight) {

        return UIEdgeInsetsMake(
            SC16_CROP_TOP,
            0.0,
            SC16_CROP_BOTTOM,
            0.0
        );
    }

    return UIEdgeInsetsMake(
        SC16_CROP_TOP,
        0.0,
        SC16_CROP_BOTTOM,
        0.0
    );
}

#pragma mark - Apply

static void SC16ApplyToWindow(UIWindow *window) {
    if (!SC16IsSupportedOS())
        return;

    if (!SC16IsUsableWindow(window))
        return;

    SC16InitState();

    SC16CropView *container =
        [SC16Containers objectForKey:window];

    if (!container) {
        container =
            [[SC16CropView alloc]
                initWithFrame:window.bounds];

        container.backgroundColor = UIColor.clearColor;
        container.opaque = NO;
        container.clipsToBounds = YES;

        /*
         * Lưu container.
         */
        [SC16Containers setObject:container
                           forKey:window];

        /*
         * Không lấy window.frame.
         * Không sửa window.transform.
         *
         * Chỉ bọc rootViewController.view.
         */

        UIView *rootView = window.rootViewController.view;

        if (rootView && rootView.superview == nil) {
            [window addSubview:container];

            [container addSubview:rootView];

            rootView.translatesAutoresizingMaskIntoConstraints = YES;
        }
    }

    container.frame = window.bounds;

    container.cropInsets =
        SC16InsetsForWindow(window);

    [container setNeedsLayout];
    [container layoutIfNeeded];
}

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!scene)
        return;

    if (@available(iOS 13.0, *)) {
        UISceneActivationState state =
            scene.activationState;

        if (state == UISceneActivationStateUnattached ||
            state == UISceneActivationStateBackground) {
            return;
        }
    }

    /*
     * Chỉ xử lý application windows.
     * Không đụng vào các window của Control Center /
     * Notification Center / SpringBoard.
     */

    for (UIWindow *window in scene.windows) {
        if (!SC16IsUsableWindow(window))
            continue;

        if (!window.rootViewController)
            continue;

        SC16ApplyToWindow(window);
    }
}

static void SC16ApplyAll(void) {
    if (!SC16IsSupportedOS())
        return;

    UIApplication *application =
        UIApplication.sharedApplication;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {

            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            SC16ApplyScene(windowScene);
        }
    }
}

#pragma mark - Orientation

static void SC16ScheduleApply(void) {
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyAll();
        }
    );
}

#pragma mark - Hooks

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (!SC16IsSupportedOS())
        return;

    /*
     * Chờ UIKit hoàn tất window layout trước khi
     * đưa root view vào crop container.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            SC16ApplyToWindow(self);
        }
    );
}

%end

#pragma mark - Scene notifications

%ctor {
    @autoreleasepool {

        if (!SC16IsSupportedOS())
            return;

        SC16InitState();

        /*
         * Không gọi ngay lúc constructor.
         * UIKit lúc này có thể chưa tạo window/scene.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ApplyAll();
            }
        );

        NSNotificationCenter *center =
            NSNotificationCenter.defaultCenter;

        [center addObserverForName:
                    UIApplicationDidBecomeActiveNotification
                              object:nil
                               queue:
                    [NSOperationQueue mainQueue]
                          usingBlock:
        ^(__unused NSNotification *notification) {

            SC16ScheduleApply();
        }];

        if (@available(iOS 13.0, *)) {

            [center addObserverForName:
                        UISceneDidActivateNotification
                                  object:nil
                                   queue:
                        [NSOperationQueue mainQueue]
                              usingBlock:
            ^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene
                        isKindOfClass:
                        [UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

            [center addObserverForName:
                        UISceneWillEnterForegroundNotification
                                  object:nil
                                   queue:
                        [NSOperationQueue mainQueue]
                              usingBlock:
            ^(NSNotification *notification) {

                UIScene *scene = notification.object;

                if ([scene
                        isKindOfClass:
                        [UIWindowScene class]]) {

                    SC16ApplyScene(
                        (UIWindowScene *)scene
                    );
                }
            }];

            [center addObserverForName:
                        UIDeviceOrientationDidChangeNotification
                                  object:nil
                                   queue:
                        [NSOperationQueue mainQueue]
                              usingBlock:
            ^(__unused NSNotification *notification) {

                /*
                 * UIKit đã cập nhật orientation.
                 * Re-layout crop container.
                 */
                SC16ScheduleApply();
            }];
        }
    }
}
