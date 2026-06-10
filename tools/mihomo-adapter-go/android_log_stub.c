#include <android/log.h>
#include <stdio.h>

int __android_log_vprint(int prio, const char* tag, const char* fmt, va_list ap) {
    printf("[%s] ", tag);
    vprintf(fmt, ap);
    printf("\n");
    return 1;
}

int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int res = __android_log_vprint(prio, tag, fmt, ap);
    va_end(ap);
    return res;
}

int __android_log_write(int prio, const char* tag, const char* text) {
    printf("[%s] %s\n", tag, text);
    return 1;
}
