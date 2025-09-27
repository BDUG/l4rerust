fn main() {
    let mut build = cc::Build::new();
    build.include("include");
    build.include("../../src/l4rust/libl4re-wrapper/include");
    build.file("src/epoll.c");
    build.file("src/eventfd.c");
    build.file("src/signalfd.c");
    build.file("src/timerfd.c");
    build.file("src/inotify.c");
    build.file("src/aio.c");
    build.compile("l4re_libc_c");
}
