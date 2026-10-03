#ifndef VGLYPH_FONT_FALLBACK_COMPAT_H
#define VGLYPH_FONT_FALLBACK_COMPAT_H

#include <fontconfig/fontconfig.h>
#include <pango/pangofc-fontmap.h>
#include <string.h>

/* Pango itemization requests the generic "emoji" family even when the text
 * description names explicit fallback families. Keep application preferences
 * local to this font map, including outline emoji for a legacy text profile. */
static void vglyph_emoji_substitute(FcPattern *pattern, gpointer data) {
    FcValue family;
    FcValueBinding binding;
    int index = 0;
    int is_emoji = 0;
    while (FcPatternGetWithBinding(pattern, FC_FAMILY, index++, &family, &binding) == FcResultMatch) {
        /* Fontconfig also appends a weak "emoji" alias to ordinary family
         * lists that include an emoji fallback. Only Pango's strong generic
         * request may replace the primary family. */
        if (binding == FcValueBindingStrong && family.type == FcTypeString &&
            strcmp((const char *)family.u.s, "emoji") == 0) {
            is_emoji = 1;
            break;
        }
    }
    if (!is_emoji) return;

    FcPatternDel(pattern, FC_FAMILY);
    for (char **preferred = (char **)data; *preferred; ++preferred) {
        FcPatternAddString(pattern, FC_FAMILY, (FcChar8 *)*preferred);
    }
    FcPatternAddString(pattern, FC_FAMILY, (const FcChar8 *)"emoji");
    /* Variation selectors may otherwise force color fonts ahead of explicit
     * outline preferences. The caller opts into this application profile. */
    FcPatternDel(pattern, FC_COLOR);
}

static void vglyph_emoji_families_free(gpointer data) {
    g_strfreev((char **)data);
}

static void vglyph_font_map_set_emoji_families(PangoFcFontMap *fontmap,
                                              const char *families) {
    if (!families || !*families) {
        pango_fc_font_map_set_default_substitute(fontmap, NULL, NULL, NULL);
        return;
    }
    char **preferred = g_strsplit(families, ",", -1);
    pango_fc_font_map_set_default_substitute(fontmap, vglyph_emoji_substitute,
                                            preferred, vglyph_emoji_families_free);
}

#endif
