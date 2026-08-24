#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges Objective-C exceptions into something Swift can handle.
///
/// AVFoundation raises NSExceptions for internal assertion failures — most
/// notably `installTapOnBus:` when the tap format doesn't match the node's
/// current hardware format. Swift's `try` cannot catch those, so an otherwise
/// recoverable audio hiccup terminated the whole app with SIGABRT and no
/// message. Running the call through here turns it into a returned NSError.
@interface ObjCExceptionCatcher : NSObject

/// Runs `block`, returning nil on success or the raised exception as an
/// NSError. Only use this around Apple framework calls that are documented to
/// raise; it is not a general-purpose error mechanism.
+ (nullable NSError *)tryBlock:(NS_NOESCAPE dispatch_block_t)block
    NS_SWIFT_NAME(try(_:));

@end

NS_ASSUME_NONNULL_END
