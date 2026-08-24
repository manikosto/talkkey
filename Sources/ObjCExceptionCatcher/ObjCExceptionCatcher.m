#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (nullable NSError *)tryBlock:(NS_NOESCAPE dispatch_block_t)block {
    @try {
        block();
        return nil;
    }
    @catch (NSException *exception) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
        info[@"ExceptionName"] = exception.name;
        if (exception.userInfo) { info[@"ExceptionUserInfo"] = exception.userInfo; }
        return [NSError errorWithDomain:@"TalkKey.ObjCException" code:1 userInfo:info];
    }
}

@end
