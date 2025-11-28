const std = @import("std");
const Reader = @import("reader.zig").Reader;
const Expr = @import("reader.zig").Expr;

const Env = @import("eval.zig").Env;
const EvalError = @import("eval.zig").EvalError;

const Tree = @import("tree.zig").Tree;
const Node = @import("tree.zig").Node;

const run = @import("root.zig").run;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const path = "programs/demo3.el";
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const src = try file.readToEndAlloc(alloc, 1 << 20);
    defer alloc.free(src);

    var ctx = try run(alloc, src);
    defer ctx.tree.deinit();
    defer ctx.env.deinit();

    const result = ctx.env.get("!result") orelse {
        std.debug.print("No result.\n", .{});
        return;
    };

    std.debug.print("Result Node ID = {d}\n", .{result});
}
