#ifndef UI2_WEBVIEW_DARWIN_H
#define UI2_WEBVIEW_DARWIN_H

void *ui2_webview_new(const char *, const char *, const char *, int, int, int);
void *ui2_webview_object(void *);
void ui2_webview_load(void *, const char *);
void ui2_webview_eval(void *, const char *);
char *ui2_webview_js_value(void *);
char *ui2_webview_cookie(void *, const char *, const char *);
void ui2_webview_clear_data(void *);
void ui2_webview_close(void *);
int ui2_webview_is_open(void *);

#endif
