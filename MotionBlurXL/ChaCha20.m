#import "ChaCha20.h"
#import "ChaCha20ObjC.h"
#import <CommonCrypto/CommonCrypto.h>
@implementation ChaCha20
#pragma mark - Public Methods
+ (NSData *)generateKeyWithAppID:(NSString *)appid {
    NSData *appidData = [appid dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *key = [NSMutableData dataWithLength:CHACHA20_KEY_LENGTH];
    if (appidData.length >= CHACHA20_KEY_LENGTH) {
        [key replaceBytesInRange:NSMakeRange(0, CHACHA20_KEY_LENGTH) withBytes:appidData.bytes];
    } else {
        [key replaceBytesInRange:NSMakeRange(0, appidData.length) withBytes:appidData.bytes];
        uint8_t zero = '0';
        for (NSUInteger i = appidData.length; i < CHACHA20_KEY_LENGTH; i++) {
            [key replaceBytesInRange:NSMakeRange(i, 1) withBytes:&zero];
        }
    }
    return [key copy];
}
+ (NSString *)encryptPlaintext:(NSString *)plaintext withKey:(NSData *)key {
    NSData *plaintextData = [plaintext dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *nonce = [NSMutableData dataWithLength:CHACHA20_NONCE_LENGTH];
    int result = SecRandomCopyBytes(kSecRandomDefault, CHACHA20_NONCE_LENGTH, nonce.mutableBytes);
    if (result != errSecSuccess) {
        NSLog(@"Failed to generate random nonce");
        return nil;
    }
    NSData *ciphertext = [self chacha20Crypt:plaintextData withKey:key nonce:nonce];
    if (!ciphertext) {
        return nil;
    }
    NSString *nonceBase64 = [nonce base64EncodedStringWithOptions:0];
    NSString *cipherBase64 = [ciphertext base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"%@.%@", nonceBase64, cipherBase64];
}
+ (NSString *)decryptEncryptedData:(NSString *)encryptedData withKey:(NSData *)key {
    NSArray *parts = [encryptedData componentsSeparatedByString:@"."];
    if (parts.count != 2) {
        return nil;
    }
    NSString *nonceBase64 = parts[0];
    NSString *cipherBase64 = parts[1];
    NSData *nonce = [[NSData alloc] initWithBase64EncodedString:nonceBase64 options:0];
    NSData *ciphertext = [[NSData alloc] initWithBase64EncodedString:cipherBase64 options:0];
    if (!nonce || !ciphertext || nonce.length != CHACHA20_NONCE_LENGTH) {
        return nil;
    }
    NSData *plaintextData = [self chacha20Crypt:ciphertext withKey:key nonce:nonce];
    if (!plaintextData) {
        return nil;
    }
    return [[NSString alloc] initWithData:plaintextData encoding:NSUTF8StringEncoding];
}
#pragma mark - Private Methods
+ (uint32_t)rotateLeft:(uint32_t)value amount:(int)amount {
    return (value << amount) | (value >> (32 - amount));
}
+ (void)quarterRoundWithState:(uint32_t *)state a:(int)a b:(int)b c:(int)c d:(int)d {
    state[a] = state[a] + state[b];
    state[d] = [self rotateLeft:state[d] ^ state[a] amount:16];
    state[c] = state[c] + state[d];
    state[b] = [self rotateLeft:state[b] ^ state[c] amount:12];
    state[a] = state[a] + state[b];
    state[d] = [self rotateLeft:state[d] ^ state[a] amount:8];
    state[c] = state[c] + state[d];
    state[b] = [self rotateLeft:state[b] ^ state[c] amount:7];
}
+ (NSData *)chacha20BlockWithKey:(NSData *)key nonce:(NSData *)nonce counter:(uint32_t)counter {
    uint32_t state[16];
    for (int i = 0; i < 4; i++) {
        state[i] = CHACHA20_CONSTANTS[i];
    }
    const uint8_t *keyBytes = (const uint8_t *)key.bytes;
    for (int i = 0; i < 8; i++) {
        state[4 + i] = ((uint32_t)keyBytes[i * 4]) |
                       ((uint32_t)keyBytes[i * 4 + 1] << 8) |
                       ((uint32_t)keyBytes[i * 4 + 2] << 16) |
                       ((uint32_t)keyBytes[i * 4 + 3] << 24);
    }
    state[12] = counter;
    const uint8_t *nonceBytes = (const uint8_t *)nonce.bytes;
    state[13] = ((uint32_t)nonceBytes[0]) |
                ((uint32_t)nonceBytes[1] << 8) |
                ((uint32_t)nonceBytes[2] << 16) |
                ((uint32_t)nonceBytes[3] << 24);
    state[14] = ((uint32_t)nonceBytes[4]) |
                ((uint32_t)nonceBytes[5] << 8) |
                ((uint32_t)nonceBytes[6] << 16) |
                ((uint32_t)nonceBytes[7] << 24);
    state[15] = ((uint32_t)nonceBytes[8]) |
                ((uint32_t)nonceBytes[9] << 8) |
                ((uint32_t)nonceBytes[10] << 16) |
                ((uint32_t)nonceBytes[11] << 24);
    uint32_t workingState[16];
    memcpy(workingState, state, sizeof(state));
    for (int round = 0; round < 10; round++) {
        [self quarterRoundWithState:workingState a:0 b:4 c:8 d:12];
        [self quarterRoundWithState:workingState a:1 b:5 c:9 d:13];
        [self quarterRoundWithState:workingState a:2 b:6 c:10 d:14];
        [self quarterRoundWithState:workingState a:3 b:7 c:11 d:15];
        [self quarterRoundWithState:workingState a:0 b:5 c:10 d:15];
        [self quarterRoundWithState:workingState a:1 b:6 c:11 d:12];
        [self quarterRoundWithState:workingState a:2 b:7 c:8 d:13];
        [self quarterRoundWithState:workingState a:3 b:4 c:9 d:14];
    }
    NSMutableData *output = [NSMutableData dataWithLength:64];
    uint8_t *outputBytes = output.mutableBytes;
    for (int i = 0; i < 16; i++) {
        uint32_t result = state[i] + workingState[i];
        outputBytes[i * 4] = result & 0xFF;
        outputBytes[i * 4 + 1] = (result >> 8) & 0xFF;
        outputBytes[i * 4 + 2] = (result >> 16) & 0xFF;
        outputBytes[i * 4 + 3] = (result >> 24) & 0xFF;
    }
    return [output copy];
}
+ (NSData *)chacha20Crypt:(NSData *)input withKey:(NSData *)key nonce:(NSData *)nonce {
    NSMutableData *output = [NSMutableData dataWithLength:input.length];
    const uint8_t *inputBytes = (const uint8_t *)input.bytes;
    uint8_t *outputBytes = output.mutableBytes;
    uint32_t counter = 0;
    NSUInteger processed = 0;
    while (processed < input.length) {
        NSData *keystream = [self chacha20BlockWithKey:key nonce:nonce counter:counter];
        const uint8_t *keystreamBytes = (const uint8_t *)keystream.bytes;
        NSUInteger chunkSize = input.length - processed;
        if (chunkSize > 64) {
            chunkSize = 64;
        }
        for (NSUInteger i = 0; i < chunkSize; i++) {
            outputBytes[processed + i] = inputBytes[processed + i] ^ keystreamBytes[i];
        }
        processed += chunkSize;
        counter++;
    }
    return [output copy];
}
@end
