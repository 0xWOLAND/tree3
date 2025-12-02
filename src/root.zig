const std = @import("std");
const Reader = @import("reader.zig").Reader; // the tiny lisp reader
const Expr = @import("reader.zig").Expr;

const Env = @import("eval.zig").Env;
const evalProgram = @import("eval.zig").evalProgram;
const operators = @import("operators.zig");

const Tree = @import("tree.zig").Tree;
const Node = @import("tree.zig").Node;

pub fn run(alloc: std.mem.Allocator, src: []const u8) !struct { tree: Tree, env: Env } {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var r = Reader.init(a, src);
    const exprs = try r.readProgram();

    var tree = try Tree.init(alloc);
    errdefer tree.deinit();

    var env = Env.init(alloc);
    errdefer env.deinit();

    try env.put("t", try tree.insert(Node.stem(0)));
    try env.put("leaf", try tree.insert(Node.leaf()));
    try operators.init(&env, &tree);

    _ = try evalProgram(&tree, &env, exprs);

    return .{ .tree = tree, .env = env };
}
