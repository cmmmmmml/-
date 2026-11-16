#import "AislingVerify.h"
#import "ChaCha20ObjC.h"
#import <CommonCrypto/CommonCrypto.h>
#import <UIKit/UIKit.h>
#import <sys/mount.h>
#import <sys/stat.h>
#define XLMB_API      @"https://card.ais666.cn/verifyKey/v2"
#define XLMB_APPID    @"1e2a32b212ee2f23d6dde0a9707b2764"
#define XLMB_APPID_ID @"2"
#define XLMB_TIME_TOLERANCE 30.0
static NSString *XLMBHex(const unsigned char *buf, size_t len) {
    NSMutableString *s = [NSMutableString stringWithCapacity:len * 2];
    for (size_t i = 0; i < len; i++) {
        [s appendFormat:@"%02x", buf[i]];
    }
    return s;
}
static NSString *XLMBSHA256Hex(NSString *input) {
    NSData *d = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, h);
    return XLMBHex(h, CC_SHA256_DIGEST_LENGTH);
}
static NSString *XLMBPercentEncode(NSString *s) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}
static NSString *XLMBDeviceIdentity(void) {
    struct statfs buf;
    if (statfs("/", &buf) == 0) {
        const char *prefix = "com.apple.os.update-";
        if (strstr(buf.f_mntfromname, prefix) != NULL) {
            const char *rest = buf.f_mntfromname + strlen(prefix);
            NSString *raw = [NSString stringWithUTF8String:rest];
            if (raw.length >= 36) {
                NSMutableString *u = [[raw substringToIndex:36] mutableCopy];
                [u replaceCharactersInRange:NSMakeRange(8, 1)  withString:@"-"];
                [u replaceCharactersInRange:NSMakeRange(13, 1) withString:@"-"];
                [u replaceCharactersInRange:NSMakeRange(18, 1) withString:@"-"];
                [u replaceCharactersInRange:NSMakeRange(23, 1) withString:@"-"];
                return u;
            }
        }
    }
    NSData *log = [NSData dataWithContentsOfFile:@"/var/mobile/Library/Logs/AppleSupport/general.log"];
    if (log.length) {
        NSString *txt = [[NSString alloc] initWithData:log encoding:NSUTF8StringEncoding];
        if (txt.length) {
            NSRegularExpression *re = [NSRegularExpression
                regularExpressionWithPattern:@"serial\":\"(.*?)\"" options:NSRegularExpressionCaseInsensitive error:nil];
            NSTextCheckingResult *m = [re firstMatchInString:txt options:0 range:NSMakeRange(0, txt.length)];
            if (m) return [txt substringWithRange:[m rangeAtIndex:1]];
        }
    }
    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    return idfv.length ? idfv : @"unknown-device";
}
@interface AislingVerify ()
@property (nonatomic, strong) NSURLSession *session;
@end
@implementation AislingVerify
+ (instancetype)shared {
    static AislingVerify *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[AislingVerify alloc] init];
        shared.appid = XLMB_APPID;
        shared.appId = XLMB_APPID_ID;
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 30;
        cfg.timeoutIntervalForResource = 30;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": @"KeyVerifier/1.0",
                                       @"Accept": @"application/json" };
        shared.session = [NSURLSession sessionWithConfiguration:cfg];
    });
    return shared;
}
#pragma mark - 签名
- (NSString *)signForTimestamp:(NSString *)timestamp code:(NSString *)code uuid:(NSString *)uuid {
    return XLMBSHA256Hex([NSString stringWithFormat:@"%@%@%@%@%@",
                          timestamp, code, uuid, self.appId, self.appid]);
}
- (BOOL)validTimestamp:(id)timestamp {
    NSString *s = nil;
    if ([timestamp isKindOfClass:[NSString class]]) s = timestamp;
    else if ([timestamp isKindOfClass:[NSNumber class]]) s = [timestamp stringValue];
    if (s.length == 0) return NO;
    return fabs([[NSDate date] timeIntervalSince1970] - [s doubleValue]) <= XLMB_TIME_TOLERANCE;
}
- (BOOL)validCheck:(NSString *)check timestamp:(id)timestamp code:(NSString *)code uuid:(NSString *)uuid {
    NSString *ts = [timestamp isKindOfClass:[NSString class]] ? timestamp : [timestamp stringValue];
    return [check isEqualToString:XLMBSHA256Hex([NSString stringWithFormat:@"%@%@%@", ts, code, uuid])];
}
#pragma mark - 请求
- (NSData *)bodyForCode:(NSString *)code key:(NSData *)key {
    NSString *uuid = XLMBDeviceIdentity();
    NSString *timestamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSDictionary *payload = @{
        @"code": code ?: @"",
        @"uuid": uuid ?: @"",
        @"timestamp": timestamp,
        @"sign": [self signForTimestamp:timestamp code:code ?: @"" uuid:uuid ?: @""],
        @"sign_type": @"sha256",
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return nil;
    NSString *plain = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *enc = [ChaCha20 encryptPlaintext:plain withKey:key];
    if (!enc.length) return nil;
    NSString *body = [NSString stringWithFormat:@"id=%@&appid=%@&data=%@",
                      self.appId, self.appid, XLMBPercentEncode(enc)];
    return [body dataUsingEncoding:NSUTF8StringEncoding];
}
- (void)verifyKey:(NSString *)code
       completion:(void (^)(BOOL, NSString *_Nullable, NSString *_Nullable))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *key = [ChaCha20 generateKeyWithAppID:self.appid];
        NSData *body = key ? [self bodyForCode:code key:key] : nil;
        if (!body) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"请求构建失败", nil); });
            return;
        }
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:XLMB_API]];
        req.HTTPMethod = @"POST";
        req.HTTPBody = body;
        [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        [req setValue:[NSString stringWithFormat:@"%lu", (unsigned long)body.length] forHTTPHeaderField:@"Content-Length"];
        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
            completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            if (err) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"网络错误", nil); });
                return;
            }
            NSInteger code2 = [(NSHTTPURLResponse *)resp statusCode];
            if (code2 != 200) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, [NSString stringWithFormat:@"服务器错误: %ld", (long)code2], nil);
                });
                return;
            }
            if (!data.length) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"响应为空", nil); });
                return;
            }
            [self handleResponse:data key:key completion:completion];
        }];
        [task resume];
    });
}
- (void)handleResponse:(NSData *)data key:(NSData *)key
            completion:(void (^)(BOOL, NSString *_Nullable, NSString *_Nullable))completion {
    NSDictionary *envelope = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![envelope isKindOfClass:[NSDictionary class]]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"响应格式错误", nil); });
        return;
    }
    NSString *cipher = envelope[@"data"];
    NSDictionary *plain = envelope;
    if ([cipher isKindOfClass:[NSString class]] && cipher.length) {
        NSString *dec = [ChaCha20 decryptEncryptedData:cipher withKey:key];
        if (!dec.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"响应解密失败", nil); });
            return;
        }
        plain = [NSJSONSerialization JSONObjectWithData:[dec dataUsingEncoding:NSUTF8StringEncoding]
                                                options:0 error:nil];
        if (![plain isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"响应数据无效", nil); });
            return;
        }
    }
    NSNumber *ok = plain[@"success"];
    if (![ok isKindOfClass:[NSNumber class]]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"缺少成功状态", nil); });
        return;
    }
    NSString *message = [plain[@"message"] isKindOfClass:[NSString class]] ? plain[@"message"] : nil;
    NSString *expiry  = [plain[@"expiry"]  isKindOfClass:[NSString class]] ? plain[@"expiry"]  : nil;
    if (!ok.boolValue) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, message ?: @"验证失败", nil); });
        return;
    }
    id serverTime = plain[@"usertime"];
    if (![self validTimestamp:serverTime]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"响应时间戳异常", nil); });
        return;
    }
    NSString *rcode  = [plain[@"code"]  isKindOfClass:[NSString class]] ? plain[@"code"]  : nil;
    NSString *ruuid  = [plain[@"uuid"]  isKindOfClass:[NSString class]] ? plain[@"uuid"]  : nil;
    NSString *rcheck = [plain[@"check"] isKindOfClass:[NSString class]] ? plain[@"check"] : nil;
    if (!rcode || !ruuid || !rcheck) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"响应数据不完整", nil); });
        return;
    }
    if (![self validCheck:rcheck timestamp:serverTime code:rcode uuid:ruuid]) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"响应签名无效", nil); });
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, message ?: @"验证成功", expiry); });
}
- (BOOL)verifyKeySync:(NSString *)code {
    __block BOOL result = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self verifyKey:code completion:^(BOOL success, NSString *msg, NSString *expiry) {
        result = success;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35 * NSEC_PER_SEC)));
    return result;
}
@end
