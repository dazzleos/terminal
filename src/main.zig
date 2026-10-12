//! Dazzle's terminal app: an interactive shell with built-in command-line
//! tools (`ls`, `cp`, `mv`, `rm`, `rmdir`, `mkdir`, `cat`, `grep`, `find`,
//! `ps`, `df`, `free`, and more). Since Dazzle has no separate `/bin/sh` or
//! standalone CLI binaries, every tool runs directly inside this terminal.
//!
//!     dazzle-terminal [directory]

const std = @import("std");
const sys = @import("sys");
const locale = @import("locale");
const app = @import("app");
const ui = @import("ui");
const shell_mod = @import("shell.zig");
const commands = @import("commands.zig");
const view = @import("view.zig");

const print = sys.print;

pub fn main(init: std.process.Init.Minimal) u8 {
    sys.logToKmsgIfStderr();
    var args = init.args.iterate();
    _ = args.skip();
    const initial_dir: ?[:0]const u8 = if (args.next()) |p| std.mem.span(p.ptr) else null;
    run(init, initial_dir) catch |err| {
        print(sys.log_error ++ "dazzle-terminal: error: {s}\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

fn run(init: std.process.Init.Minimal, initial_dir: ?[:0]const u8) !void {
    locale.current = locale.load().language;
    const gpa = std.heap.page_allocator;
    const a = try ui.App.open(gpa, init.environ, .{
        .title = "Terminal",
        .app_id = "dazzle-terminal",
        .size = view.open_size,
        .min_size = view.min_size,
    });
    defer a.close();

    // Build launch environment for apps opened via `open`.
    var child_env: app.ChildEnv = undefined;
    const start_dir: ?[]const u8 = initial_dir orelse if (commands.statPath(sys.system.user_dir, true)) |st|
        (if (st.isDir()) @as(?[]const u8, sys.system.user_dir) else null)
    else |_|
        null;

    var sh = try shell_mod.Shell.init(gpa, start_dir, child_env.init(init.environ, sys.system.user_dir));
    defer sh.deinit();

    while (try a.step(60 * std.time.ns_per_s)) {
        if (sh.should_exit) return;
        const now = sys.nowNs();
        a.takeInput();
        if (sh.should_exit or a.controls.quit) return;
        try a.draw(now, view.Terminal{
            .shell = &sh,
            .on_close = .of(&a.controls, app.Controls.close),
        });
    }
}

test {
    _ = commands;
    _ = shell_mod;
    _ = view;
}
