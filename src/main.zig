//! Dazzle's terminal app: an interactive shell with built-in command-line
//! tools (`ls`, `cp`, `mv`, `rm`, `rmdir`, `mkdir`, `cat`, `grep`, `find`,
//! `ps`, `df`, `free`, and more). Since Dazzle has no separate `/bin/sh` or
//! standalone CLI binaries, every tool runs directly inside this terminal.
//!
//!     dazzle-terminal [directory]

const std = @import("std");
const sys = @import("sys");
const app = @import("app");
const kete = @import("kete");
const kete_vc4 = @import("kete_vc4");
const shell_mod = @import("shell.zig");
const commands = @import("commands.zig");
const view = @import("view.zig");

const print = sys.print;

pub fn main(init: std.process.Init) u8 {
    sys.logToKmsgIfStderr();
    var args = init.minimal.args.iterate();
    _ = args.skip();
    const initial_dir: ?[:0]const u8 = if (args.next()) |p| std.mem.span(p.ptr) else null;
    run(init, initial_dir) catch |err| {
        print(sys.log_error ++ "dazzle-terminal: error: {s}\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

/// The window's root: the shell, and closing the window (`exit`).
const Root = struct {
    shell: *shell_mod.Shell,
    window: ?*kete.App.Window = null,

    pub fn build(r: *const Root, cx: *kete.BuildContext) kete.Widget {
        return cx.make(view.Terminal{
            .shell = r.shell,
            .on_close = if (r.window) |w| .of(w, close) else null,
        });
    }

    fn close(w: *kete.App.Window) void {
        w.close();
    }
};

fn run(init: std.process.Init, initial_dir: ?[:0]const u8) !void {
    const gpa = std.heap.page_allocator;
    var host: kete_vc4.Host = undefined;
    try host.init(gpa, init.io, init.minimal.environ, .{ .app_id = "dazzle-terminal" });
    defer host.deinit();

    // Build launch environment for apps opened via `open`.
    var child_env: app.ChildEnv = undefined;
    const start_dir: ?[]const u8 = initial_dir orelse if (commands.statPath(sys.system.user_dir, true)) |st|
        (if (st.isDir()) @as(?[]const u8, sys.system.user_dir) else null)
    else |_|
        null;

    var sh = try shell_mod.Shell.init(gpa, start_dir, child_env.init(init.minimal.environ, sys.system.user_dir));
    defer sh.deinit();

    var root: Root = .{ .shell = &sh };
    root.window = try host.app.openWindow(.{
        .title = "Terminal",
        .root = .of(&root),
        .size = view.open_size,
        .min_size = view.min_size,
        .on_close_request = .close,
    });

    while (try host.step(60 * std.time.ns_per_s)) {
        if (sh.should_exit) return;
    }
}

test {
    _ = commands;
    _ = shell_mod;
    _ = view;
}
