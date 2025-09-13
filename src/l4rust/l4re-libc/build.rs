fn main() {
    cc::Build::new()
        .include("include")
        .file("src/epoll.c")
        .compile("l4re_libc_epoll");
}
