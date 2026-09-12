#import <UIKit/UIKit.h>

static CGFloat const SC16_TOP_CROP = 60.0;
static CGFloat const SC16_BOTTOM_CROP = 60.0;

static BOOL SC16Enabled(void) {
    NSString *version = UIDevice.currentDevice.systemVersion;
    return [version hasPrefix:@"16.4"];
}

static void SC16ApplyCrop(UIWindow *window) {
    if (!SC16Enabled() || !window)
        return;

    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    CGRect screenBounds = screen.bounds;

    CGFloat width = CGRectGetWidth(screenBounds);
    CGFloat height = CGRectGetHeight(screenBounds);

    if (height <= SC16_TOP_CROP + SC16_BOTTOM_CROP)
        return;

    /*
     * Không scale.
     * Không kéo giãn.
     * Giữ transform 1:1.
     */
    window.transform = CGAffineTransformIdentity;

    CGRect frame = window.frame;

    frame.origin.x = 0.0;
    frame.origin.y = SC16_TOP_CROP;

    frame.size.width = width;
    frame.size.height =
        height - SC16_TOP_CROP - SC16_BOTTOM_CROP;

    window.frame = frame;
}

static void SC16ApplyScene(UIWindowScene *scene) {
    if (!SC16Enabled() || !scene)
        return;

    for (UIWindow *window in scene.windows) {
        if (!window.hidden) {
            SC16ApplyCrop(window);
        }
    }
}

static void SC16ApplyAllScenes(void) {
    if (!SC16Enabled())
        return;

    UIApplication *app = UIApplication.sharedApplication;

    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        if (windowScene.activationState ==
            UISceneActivationStateUnattached)
            continue;

        SC16ApplyScene(windowScene);
    }
}

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (SC16Enabled()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyCrop(self);
        });
    }
}

- (void)setFrame:(CGRect)frame {
    %orig(frame);

    if (SC16Enabled()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyCrop(self);
        });
    }
}

%end

%ctor {
    @autoreleasepool {
        if (!SC16Enabled())
            return;

        dispatch_async(dispatch_get_main_queue(), ^{
            SC16ApplyAllScenes();
        });

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {
                SC16ApplyAllScenes();
            }];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneDidActivateNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *notification) {
                UIScene *scene = notification.object;

                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    SC16ApplyScene((UIWindowScene *)scene);
                }
            }];
    }
}
