#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface AislingVerify : NSObject
@property (nonatomic, copy) NSString *appid;
@property (nonatomic, copy) NSString *appId;
+ (instancetype)shared;
- (void)verifyKey:(NSString *)code
       completion:(void (^)(BOOL success, NSString *_Nullable message, NSString *_Nullable expiry))completion;
- (BOOL)verifyKeySync:(NSString *)code;
@end
NS_ASSUME_NONNULL_END
