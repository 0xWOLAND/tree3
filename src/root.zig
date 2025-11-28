const std = @import("std");
const Reader = @import("reader.zig").Reader; // the tiny lisp reader
const Expr = @import("reader.zig").Expr;

const Env = @import("eval.zig").Env;
const evalProgram = @import("eval.zig").evalProgram;
const EvalError = @import("eval.zig").EvalError;

const Tree = @import("tree.zig").Tree;
const Node = @import("tree.zig").Node;

fn run(alloc: std.mem.Allocator, src: []const u8) !struct { tree: Tree, env: Env } {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var r = Reader.init(a, src);
    const exprs = try r.readProgram();

    var tree = try Tree.init(alloc);
    errdefer tree.deinit();

    var env = Env.init(alloc);
    errdefer env.deinit();

    _ = try evalProgram(&tree, &env, exprs);

    return .{ .tree = tree, .env = env };
}

test "double twice using t application" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const src =
        \\(define x 3)
        \\(define twice (t))
        \\(twice (twice x))
    ;

    var ctx = try run(alloc, src);
    defer ctx.tree.deinit();
    defer ctx.env.deinit();

    // x is encoded number 3 - some forked structure
    const id_x = ctx.env.get("x").?;
    const node_x = ctx.tree.get(id_x);
    try std.testing.expect(node_x.kind != .Leaf);

    // result should be t(t(x)) - a Stem whose rhs is a Stem whose rhs is x
    const result = ctx.env.get("!result").?;
    const n1 = ctx.tree.get(result);
    try std.testing.expect(n1.kind == .Stem);

    const inner = n1.rhs.?;
    const n2 = ctx.tree.get(inner);
    try std.testing.expect(n2.kind == .Stem);

    const inner2 = n2.rhs.?;
    try std.testing.expectEqual(id_x, inner2);
}

test "nested lists and comments" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const src =
        \\; a comment
        \\(define a (list 1 (list 2 3) 4)) ; inline comment
        \\a
    ;

    var ctx = try run(alloc, src);
    defer ctx.tree.deinit();
    defer ctx.env.deinit();

    const a_id = ctx.env.get("a").?;
    const res_id = ctx.env.get("!result").?;

    // result should be the same as a
    try std.testing.expectEqual(a_id, res_id);

    // its root must be a fork, since it's a non-empty list
    const node = ctx.tree.get(a_id);
    try std.testing.expect(node.kind == .Fork);
}

test "rebinding same value is allowed but different is an error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const ok_src =
        \\(define x 11)
        \\(define x 11) ; identical rebinding
        \\x
    ;

    var ok_ctx = try run(alloc, ok_src);
    defer ok_ctx.tree.deinit();
    defer ok_ctx.env.deinit();

    const id_x = ok_ctx.env.get("x").?;
    const id_res = ok_ctx.env.get("!result").?;
    try std.testing.expectEqual(id_x, id_res);

    // but different rebinding must fail
    const bad_src =
        \\(define y 7)
        \\(define y 9)
    ;

    // expect RebindImmutable error
    try std.testing.expectError(EvalError.RebindImmutable, run(alloc, bad_src));
}
