#include <stdio.h>

extern "C" {
    void printk(const char *fmt, ...);
    void module_init(int (*init)(void));
    void module_exit(void (*exit)(void));
}

static int my_init(void) {
    printk("driver init\n");
    return 0;
}

static void my_exit(void) {
    printk("driver exit\n");
}

extern "C" void l4re_driver_start(void) {
    module_init(my_init);
    module_exit(my_exit);
}
