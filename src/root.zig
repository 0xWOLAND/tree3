const std = @import("std");
const Reader = @import("reader.zig").Reader; // the tiny lisp reader
const Expr = @import("reader.zig").Expr;

const Env = @import("eval.zig").Env;
const evalProgram = @import("eval.zig").evalProgram;
const EvalError = @import("eval.zig").EvalError;
const operators = @import("operators.zig");

const Tree = @import("tree.zig").Tree;
const Node = @import("tree.zig").Node;
const Id = @import("tree.zig").Id;

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

    const bad_src =
        \\(define y 7)
        \\(define y 9)
    ;

    try std.testing.expectError(EvalError.RebindImmutable, run(alloc, bad_src));
}

test "define-rec builds a cycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const src =
        \\(define-rec self (t self))
        \\self
    ;

    var ctx = try run(alloc, src);
    defer ctx.tree.deinit();
    defer ctx.env.deinit();

    const self_id = ctx.env.get("self").?;
    const self_node = ctx.tree.get(self_id);
    try std.testing.expect(self_node.kind == .Stem);
    try std.testing.expectEqual(self_id, self_node.rhs.?);

    const res = ctx.env.get("!result").?;
    try std.testing.expectEqual(self_id, res);
}

test "pair builds a fork from two args" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const src =
        \\(define p (pair leaf leaf))
        \\p
    ;

    var ctx = try run(alloc, src);
    defer ctx.tree.deinit();
    defer ctx.env.deinit();

    const leaf_id = ctx.env.get("leaf").?;
    const p_id = ctx.env.get("p").?;
    const node = ctx.tree.get(p_id);
    try std.testing.expect(node.kind == .Fork);
    try std.testing.expectEqual(leaf_id, node.lhs.?);
    try std.testing.expectEqual(leaf_id, node.rhs.?);
}

test "first and second project from pair" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const src =
        \\(define p (pair leaf (pair leaf leaf)))
        \\(define a (first p))
        \\(define b (second p))
        \\(list a b)
    ;

    var ctx = try run(alloc, src);
    defer ctx.tree.deinit();
    defer ctx.env.deinit();

    const leaf_id = ctx.env.get("leaf").?;
    const a_id = ctx.env.get("a").?;
    const b_id = ctx.env.get("b").?;
    try std.testing.expectEqual(leaf_id, a_id);

    const pair_id = ctx.env.get("p").?;
    const pair_node = ctx.tree.get(pair_id);
    try std.testing.expect(pair_node.kind == .Fork);
    try std.testing.expectEqual(pair_node.rhs.?, b_id);

    const result_list = ctx.env.get("!result").?;
    const head = ctx.tree.get(result_list);
    try std.testing.expect(head.kind == .Fork);
    try std.testing.expectEqual(a_id, head.lhs.?);

    const tail = ctx.tree.get(head.rhs.?);
    try std.testing.expect(tail.kind == .Fork);
    try std.testing.expectEqual(b_id, tail.lhs.?);
}

test "self-application shape is a loop" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const src =
        \\(define-rec loop (pair loop loop))
        \\loop
    ;

    var ctx = try run(alloc, src);
    defer ctx.tree.deinit();
    defer ctx.env.deinit();

    const loop_id = ctx.env.get("loop").?;
    const n = ctx.tree.get(loop_id);
    try std.testing.expect(n.kind == .Fork);
    try std.testing.expectEqual(loop_id, n.lhs.?);
    try std.testing.expectEqual(loop_id, n.rhs.?);

    // NOTE: (loop loop) would diverge under unbounded apply
}
