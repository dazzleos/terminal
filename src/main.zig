//! Dazzle's terminal app: an interactive shell with built-in command-line
//! tools (`ls`, `cp`, `mv`, `rm`, `rmdir`, `mkdir`, `cat`, `grep`, `find`,
//! `ps`, `df`, `free`, and more). Since Dazzle has no separate `/bin/sh` or
//! standalone CLI binaries, every tool runs directly inside this terminal.
//!
//!     dazzle-terminal [directory]

const std = @import("std");
const sys = @import("sys");
const locale = @import("locale");
const font = @import("font");
const vc4 = @import("vc4");
const app = @import("app");
const ui = @import("ui");
const wayland = @import("wayland");
const shell_mod = @import("shell.zig");
const commands = @import("commands.zig");
const view = @import("view.zig");

const print = sys.print;

/// The clear colour: the dark theme's surface.
const background = 0xff141218;

var frame: vc4.render.Frame = undefined;

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
    var dev = vc4.device.openRender() catch |err| {
        print(sys.log_error ++ "dazzle-terminal: no GPU ({s})\n", .{@errorName(err)});
        return err;
    };
    const win = try openWindow(gpa, init, &dev);
    var width = win.width;
    var height = win.height;

    var font_buf: [512]u8 = undefined;
    var f: ?font.Font = blk: {
        const data = sys.readFileAlloc(gpa, sys.fontFile(&font_buf, font.default_font_file), 32 * 1024 * 1024) catch break :blk null;
        break :blk font.Font.init(data) catch null;
    };
    const window_ui = try ui.Ui.create(gpa, if (f) |*fnt| fnt else null);
    window_ui.clipboard = .of(&win.clipboard);
    try window_ui.attachGpu(dev);

    // Build launch environment for apps opened via `open`.
    var env_bufs: [3][160]u8 = undefined;
    var env: [4][*:0]const u8 = undefined;
    env[0] = "HOME=/data/user";
    var env_len: usize = 1;
    for ([_][]const u8{ "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "HOME" }, &env_bufs) |name, *buf| {
        const value = std.process.Environ.getPosix(init.environ, name) orelse continue;
        env[env_len] = (std.fmt.bufPrintZ(buf, "{s}={s}", .{ name, value }) catch continue).ptr;
        env_len += 1;
    }

    const start_dir: ?[]const u8 = initial_dir orelse if (commands.statPath(sys.system.user_dir, true)) |st|
        (if (st.isDir()) @as(?[]const u8, sys.system.user_dir) else null)
    else |_|
        null;

    var sh = try shell_mod.Shell.init(gpa, start_dir, env[0..env_len]);
    defer sh.deinit();

    var controls: app.Controls = .{ .win = win };
    win.setMinSize(view.min_size[0], view.min_size[1]);

    var dirty = true;
    var idle = false;
    var suspended = false;
    while (true) {
        const waited = if (idle) blk: {
            const timeout: u64 = if (window_ui.needs_frame and !suspended) 16 * std.time.ns_per_ms else 60 * std.time.ns_per_s;
            break :blk win.wait(timeout);
        } else win.poll();
        waited catch |err| {
            if (err == error.ServerError) print(sys.log_error ++ "dazzle-terminal: compositor error: {s}\n", .{win.conn.errorMessage()});
            return err;
        };
        if (win.closed or controls.quit or sh.should_exit) return;
        if (try win.applyConfigure()) |size| {
            width = size[0];
            height = size[1];
            dirty = true;
        }
        if (win.suspended != suspended) {
            suspended = win.suspended;
            if (suspended) win.releaseSpareBuffers() else dirty = true;
        }
        const now = sys.nowNs();
        window_ui.keyboard = win.layout;
        for (win.takeInput()) |e| switch (e) {
            .motion => |pos| window_ui.pointerMotion(pos),
            .button => |b| window_ui.pointerButton(b.pos, b.code, b.pressed),
            .key => |k| window_ui.keyEvent(k.code, k.pressed),
            .scroll => |sc| window_ui.pointerScroll(sc.pos, sc.dx, sc.dy),
            .leave => window_ui.pointerLeave(),
            .touch_down => |t| window_ui.touchDown(t.id, t.pos),
            .touch_motion => |t| window_ui.touchMotion(t.id, t.pos),
            .touch_up => |id| window_ui.touchUp(id),
            .touch_cancel => window_ui.touchCancel(),
            .relative_motion, .pointer_locked => {},
        };
        if (sh.should_exit or controls.quit) return;

        idle = true;
        if (!suspended and (dirty or window_ui.needs_frame)) {
            dirty = false;
            window_ui.fullscreen = win.fullscreen;
            window_ui.frame(width, height, now, view.Terminal{
                .shell = &sh,
                .on_close = .of(&controls, app.Controls.close),
                .on_maximize = .of(&controls, app.Controls.toggleMaximized),
                .on_drag = .of(&controls, app.Controls.drag),
                .maximized = win.maximized,
            });
            if (window_ui.changed()) {
                idle = false;
                const target = try win.beginFrame();
                const region = window_ui.repaint(win.bufferAge());
                frame.begin(target, .{ .clear = background });
                ui.Ui.limit(&frame, &region);
                try window_ui.render(&frame, win.flusher());
                try win.render(&frame);
                var damage: [ui.damage.Region.max_rects]vc4.render.Viewport = undefined;
                const changed = window_ui.damaged();
                for (changed, damage[0..changed.len]) |r, *v| v.* = .{
                    .x = @intFromFloat(r.x),
                    .y = @intFromFloat(r.y),
                    .width = @intFromFloat(r.w),
                    .height = @intFromFloat(r.h),
                };
                try win.showDamaged(damage[0..changed.len]);
            }
        }
    }
}

fn openWindow(gpa: std.mem.Allocator, init: std.process.Init.Minimal, dev: *vc4.Device) !*app.Window {
    const Environ = std.process.Environ;
    var path_buf: [128]u8 = undefined;
    const path = wayland.client.socketPath(&path_buf, Environ.getPosix(init.environ, "XDG_RUNTIME_DIR"), Environ.getPosix(init.environ, "WAYLAND_DISPLAY")) catch {
        print("dazzle-terminal: WAYLAND_DISPLAY needs XDG_RUNTIME_DIR\n", .{});
        return error.NoCompositor;
    };
    const win = app.Window.open(gpa, .device(dev), path, .{ .title = "Terminal", .size = view.open_size }) catch |err| {
        print(sys.log_warning ++ "dazzle-terminal: cannot open a window on {s} ({s})\n", .{ path, @errorName(err) });
        return err;
    };
    try win.setAppId("dazzle-terminal");
    return win;
}

test {
    _ = commands;
    _ = shell_mod;
    _ = view;
}
