#include <stdio.h>

extern void printk(const char *fmt, ...);
extern void module_init(int (*init)(void));
extern void module_exit(void (*exit)(void));

static int my_init(void) {
    printk("driver init\n");
    return 0;
}

static void my_exit(void) {
    printk("driver exit\n");
}

void l4re_driver_start(void) {
    module_init(my_init);
    module_exit(my_exit);
}
