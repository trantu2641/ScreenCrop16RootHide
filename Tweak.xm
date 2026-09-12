#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat const SC16_TOP_CROP = 34.0;
static CGFloat const SC16_BOTTOM_CROP = 34.0;
static CGFloat const SC16_CORNER_RADIUS = 2.0;


/*
 * Chỉ chạy iOS 16.4.
 */
static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;

    return [version hasPrefix:@"16.4"];
}


/*
 * Xác định orientation dựa trên geometry thật của UIScreen.
 *
 * Không dùng UIDeviceOrientation để tính kích thước.
 * Khi UIKit đổi orientation, UIScreen.bounds sẽ đổi theo.
 */
static BOOL SC16IsLandscapeRect(CGRect rect) {
    return CGRectGetWidth(rect) > CGRectGetHeight(rect);
}


/*
 * Crop UIScreen.bounds.
 *
 * Portrait:
 *
 *       34 px
 *   ┌───────────────┐
 *   │               │
 *   ├───────────────┤
 *   │               │
 *   │   APP / UI    │
 *   │               │
 *   ├───────────────┤
 *   │               │
 *   └───────────────┘
 *       34 px
 *
 *
 * Landscape:
 *
 *       34 px       34 px
 *   ┌───┬───────────┬───┐
 *   │   │           │   │
 *   │   │    UI     │   │
 *   │   │           │   │
 *   └───┴───────────┴───┘
 *
 *
 * QUAN TRỌNG:
 * Không thay đổi nativeBounds.
 * Native resolution của màn hình vẫn nguyên.
 */
static CGRect SC16CroppedScreenBounds(CGRect original) {

    if (CGRectIsEmpty(original))
        return original;

    CGFloat width =
        CGRectGetWidth(original);

    CGFloat height =
        CGRectGetHeight(original);

    if (width <= 0.0 || height <= 0.0)
        return original;


    CGFloat cropWidth = width;
    CGFloat cropHeight = height;


    if (SC16IsLandscapeRect(original)) {

        /*
         * Landscape:
         * notch và vùng home trở thành hai cạnh trái/phải.
         */
        cropWidth =
            width -
            SC16_TOP_CROP -
            SC16_BOTTOM_CROP;

    } else {

        /*
         * Portrait:
         * crop phía trên + phía dưới.
         */
        cropHeight =
            height -
            SC16_TOP_CROP -
            SC16_BOTTOM_CROP;
    }


    if (cropWidth <= 0.0 ||
        cropHeight <= 0.0) {

        return original;
    }


    /*
     * Bounds logical mới.
     *
     * Origin vẫn 0,0 để UIKit coi đây là
     * một màn hình bắt đầu từ góc trên trái
     * của vùng hiển thị mới.
     */
    return CGRectMake(
        0.0,
        0.0,
        cropWidth,
        cropHeight
    );
}


/*
 * Tỷ lệ scale đồng đều.
 *
 * Không dùng scaleX != scaleY.
 * Vì vậy hình ảnh không bị kéo méo.
 */
static CGFloat SC16UniformScale(CGRect original,
                                CGRect cropped) {

    CGFloat originalWidth =
        CGRectGetWidth(original);

    CGFloat originalHeight =
        CGRectGetHeight(original);

    CGFloat croppedWidth =
        CGRectGetWidth(cropped);

    CGFloat croppedHeight =
        CGRectGetHeight(cropped);


    if (originalWidth <= 0.0 ||
        originalHeight <= 0.0) {

        return 1.0;
    }


    CGFloat sx =
        croppedWidth / originalWidth;

    CGFloat sy =
        croppedHeight / originalHeight;


    /*
     * Một tỷ lệ duy nhất cho X/Y.
     */
    return MIN(sx, sy);
}


%hook UIScreen


/*
 * Đây là hook chính.
 *
 * UIKit gọi UIScreen.bounds để biết kích thước
 * vùng màn hình mà nó đang layout.
 */
- (CGRect)bounds {

    CGRect original =
        %orig;


    if (!SC16Enabled())
        return original;


    CGRect cropped =
        SC16CroppedScreenBounds(original);


    return cropped;
}


/*
 * applicationFrame cũng phải đồng bộ với bounds.
 *
 * Nếu chỉ sửa bounds mà applicationFrame vẫn
 * trả về geometry cũ, một số app có thể layout
 * theo kích thước khác nhau.
 */
- (CGRect)applicationFrame {

    CGRect original =
        %orig;


    if (!SC16Enabled())
        return original;


    CGRect bounds =
        SC16CroppedScreenBounds(original);


    return bounds;
}


/*
 * Không hook nativeBounds.
 *
 * nativeBounds là kích thước vật lý / native
 * của màn hình.
 *
 * Giữ nguyên nó giúp tránh phá các API liên quan
 * đến rendering và scale phần cứng.
 */


/*
 * Không hook nativeScale.
 *
 * Scale phần cứng phải giữ nguyên.
 */


%end


/*
 * ------------------------------------------------------------------
 * UIWindow
 * ------------------------------------------------------------------
 *
 * Không thay frame/bounds của UIWindow.
 *
 * Đây là điểm khác biệt quan trọng so với các bản trước.
 */
%hook UIWindow


- (void)makeKeyAndVisible {

    %orig;

    /*
     * Không chỉnh frame.
     *
     * UIScreen đã cung cấp geometry crop cho UIKit.
     */
}


- (void)setHidden:(BOOL)hidden {

    %orig(hidden);

    /*
     * Không re-layout window.
     */
}


%end


/*
 * ------------------------------------------------------------------
 * Rotation
 * ------------------------------------------------------------------
 *
 * Không ép frame.
 *
 * Chỉ yêu cầu UIKit layout lại sau khi orientation
 * đã thay đổi.
 */
static void SC16ScheduleRelayout(void) {

    if (!SC16Enabled())
        return;


    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*
             * UIScreen.bounds hiện tại sẽ được gọi lại
             * và trả về geometry crop tương ứng.
             */
            for (UIWindowScene *scene
                 in UIApplication.sharedApplication.connectedScenes) {

                if (![scene isKindOfClass:
                          [UIWindowScene class]]) {

                    continue;
                }


                if (scene.activationState ==
                    UISceneActivationStateUnattached) {

                    continue;
                }


                for (UIWindow *window
                     in scene.windows) {

                    if (!window.hidden) {

                        [window setNeedsLayout];
                        [window setNeedsDisplay];
                    }
                }
            }
        }
    );
}


%ctor {

    @autoreleasepool {

        if (!SC16Enabled())
            return;


        /*
         * Initial UIKit layout.
         */
        dispatch_async(
            dispatch_get_main_queue(),
            ^{
                SC16ScheduleRelayout();
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

                SC16ScheduleRelayout();
            }];


        /*
         * Scene activate.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ScheduleRelayout();
            }];


        /*
         * Scene foreground.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UISceneWillEnterForegroundNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                SC16ScheduleRelayout();
            }];


        /*
         * Rotation.
         *
         * Không sử dụng:
         *
         * UIWindowSceneDidUpdateNotification
         *
         * vì SDK bạn đang build không có symbol này.
         */
        [[NSNotificationCenter defaultCenter]
            addObserverForName:
                UIDeviceOrientationDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {

                /*
                 * Đợi UIKit hoàn tất orientation transition.
                 */
                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        SC16ScheduleRelayout();


                        /*
                         * Thêm một pass sau đó để bắt
                         * geometry mới của UIScreen.
                         */
                        dispatch_async(
                            dispatch_get_main_queue(),
                            ^{
                                SC16ScheduleRelayout();
                            }
                        );
                    }
                );
            }];
    }
}
