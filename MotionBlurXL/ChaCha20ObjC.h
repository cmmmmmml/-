#ifndef CHACHA20_OBJC_H
#define CHACHA20_OBJC_H
#import <Foundation/Foundation.h>
@interface ChaCha20 : NSObject
+ (NSData *)generateKeyWithAppID:(NSString *)appid;
+ (NSString *)encryptPlaintext:(NSString *)plaintext withKey:(NSData *)key;
+ (NSString *)decryptEncryptedData:(NSString *)encryptedData withKey:(NSData *)key;
@end
#endif
