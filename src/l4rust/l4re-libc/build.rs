fn main() {
    let mut build = cc::Build::new();
    build.include("include");
    build.file("src/epoll.c");
    build.file("src/eventfd.c");
    build.file("src/signalfd.c");
    build.file("src/timerfd.c");
    build.compile("l4re_libc_c");
}
