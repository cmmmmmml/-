#ifndef CHACHA20_H
#define CHACHA20_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#define CHACHA20_KEY_LENGTH 32
#define CHACHA20_NONCE_LENGTH 12
static const char base64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static const uint32_t CHACHA20_CONSTANTS[4] = {0x61707865, 0x3320646e, 0x79622d32, 0x6b206574};
void generate_chacha20_key(const char *appid, uint8_t *key);
uint32_t rotate_left(uint32_t value, int amount);
void chacha20_quarter_round(uint32_t *a, uint32_t *b, uint32_t *c, uint32_t *d);
void chacha20_block(const uint8_t key[32], const uint8_t nonce[12], uint32_t counter, uint8_t output[64]);
void chacha20_crypt(const uint8_t *input, uint8_t *output, size_t length, const uint8_t key[32], const uint8_t nonce[12]);
char *chacha20_encrypt(const char *plaintext, const uint8_t *key);
char *chacha20_decrypt(const char *encrypted_data, const uint8_t *key);
char* base64_encode(const unsigned char* data, size_t input_length, size_t* output_length);
unsigned char* base64_decode(const char* data, size_t input_length, size_t* output_length);
#endif
