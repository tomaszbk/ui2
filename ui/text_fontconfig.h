#ifndef UI2_TEXT_FONTCONFIG_H
#define UI2_TEXT_FONTCONFIG_H
#include <fontconfig/fontconfig.h>
#include <fontconfig/fcfreetype.h>
#include <stdlib.h>
#include <string.h>

static char *ui2_font_family(const char *path) {
    int count = 0;
    FcPattern *pattern = FcFreeTypeQuery((const FcChar8 *)path, 0, NULL, &count);
    if (!pattern) return NULL;
    FcChar8 *family = NULL;
    char *result = NULL;
    if (FcPatternGetString(pattern, FC_FAMILY, 0, &family) == FcResultMatch && family) {
        size_t size = strlen((const char *)family) + 1;
        result = (char *)malloc(size);
        if (result) memcpy(result, family, size);
    }
    FcPatternDestroy(pattern);
    return result;
}
#endif
