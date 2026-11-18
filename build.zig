//! Terminal, a terminal, with a shell of its own, for running command-line tools, for Dazzle: built with Dazzle's modules and
//! tools (see Dazzle's build.zig, `addApp`).
//!
//!     zig build                 the program, and its archive and catalogue (zig-out/apps)
//!     zig build test            its tests, on this computer
//!
//! With a Dazzle (or kete) checkout of your own beside it:
//! `zig build --fork=../dazzle`.

const std = @import("std");
const dazzle = @import("dazzle");

pub fn build(b: *std.Build) void {
    _ = dazzle.addApp(b, .{
        .name = "dazzle-terminal",
        .icon = .terminal,
        .title = "Terminal",
        .description = "Run command-line tools",
        .about = "Run command-line tools: look round the files, see what the system is doing, and try commands, in a terminal with its own shell.",
    });
}
