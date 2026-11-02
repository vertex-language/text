// Hyphenation points on macOS: CFStringGetHyphenationLocationBeforeIndex.
// See hyphen.cpp.
module;
#include <stdint.h>
#include <string.h>
#import <Foundation/Foundation.h>
module text.hyphen;

int32_t hyphenPoints(const char* word, const char* lang, int32_t* points, int32_t cap) noexcept {
    if (word == nullptr || lang == nullptr || points == nullptr || cap <= 0) return 0;
    @autoreleasepool {
        NSString* text = [NSString stringWithUTF8String:word];
        NSString* tag = [NSString stringWithUTF8String:lang];
        if (text == nil || tag == nil) return 0;
        CFLocaleRef locale = CFLocaleCreate(kCFAllocatorDefault, (__bridge CFStringRef)tag);
        if (locale == nullptr) return 0;
        int32_t count = 0;
        if (CFStringIsHyphenationAvailableForLocale(locale)) {
            CFStringRef s = (__bridge CFStringRef)text;
            // From the end back: each answer is the last break before where it asks.
            CFIndex at = (CFIndex)text.length;
            int32_t back[64];
            int32_t found = 0;
            while (at > 0 && found < 64) {
                CFIndex p = CFStringGetHyphenationLocationBeforeIndex(s, at, CFRangeMake(0, (CFIndex)text.length), 0, locale, nullptr);
                if (p == kCFNotFound || p <= 0) break;
                // UTF-16 to UTF-8.
                back[found++] = (int32_t)strlen([[text substringToIndex:(NSUInteger)p] UTF8String]);
                at = p;
            }
            while (found > 0 && count < cap) points[count++] = back[--found];
        }
        CFRelease(locale);
        return count;
    }
}
