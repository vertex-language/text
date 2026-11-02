// Where words may hyphenate, for package text/hyphen. macOS's is the
// system's dictionaries (hyphen_darwin.mm); elsewhere there are none yet.
module;
#include <stdint.h>
#if defined(__APPLE__)
#pragma vertex framework("CoreFoundation")
#pragma vertex framework("Foundation")
#endif
export module text.hyphen;

// The byte offsets a word may break at, into points, up to cap of them, for
// a language tag ("en", "de-AT"). Answers how many; 0 where there's no
// dictionary for it.
export int32_t hyphenPoints(const char* word, const char* lang, int32_t* points, int32_t cap) noexcept;

#if !defined(__APPLE__)
int32_t hyphenPoints(const char*, const char*, int32_t*, int32_t) noexcept { return 0; }
#endif
