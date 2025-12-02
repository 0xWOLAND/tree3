const std = @import("std");
const run = @import("root.zig").run;
const EvalError = @import("eval.zig").EvalError;
const Tree = @import("tree.zig").Tree;

const TestCtx = struct {
    tree: Tree,
    env: @import("eval.zig").Env,

    fn init(src: []const u8) !TestCtx {
        const result = try run(std.testing.allocator, src);
        return .{ .tree = result.tree, .env = result.env };
    }

    fn deinit(self: *TestCtx) void {
        self.tree.deinit();
        self.env.deinit();
    }
};

test "program: double twice builds nested stems" {
    var ctx = try TestCtx.init(
        \\(define x 3)
        \\(define twice (t))
        \\(twice (twice x))
    );
    defer ctx.deinit();

    const id_x = ctx.env.get("x").?;
    const node_x = ctx.tree.get(id_x);
    try std.testing.expect(node_x.kind != .Leaf);

    const result = ctx.env.get("!result").?;
    const n1 = ctx.tree.get(result);
    try std.testing.expect(n1.kind == .Stem);

    const inner = n1.rhs.?;
    const n2 = ctx.tree.get(inner);
    try std.testing.expect(n2.kind == .Stem);

    const inner2 = n2.rhs.?;
    try std.testing.expectEqual(id_x, inner2);
}

test "program: nested lists allow comments" {
    var ctx = try TestCtx.init(
        \\; a comment
        \\(define a (list 1 (list 2 3) 4)) ; inline comment
        \\a
    );
    defer ctx.deinit();

    const a_id = ctx.env.get("a").?;
    const res_id = ctx.env.get("!result").?;

    try std.testing.expectEqual(a_id, res_id);

    const node = ctx.tree.get(a_id);
    try std.testing.expect(node.kind == .Fork);
}

test "program: rebinding same value is allowed but different is an error" {
    const bad_src =
        \\(define y 7)
        \\(define y 9)
    ;

    try std.testing.expectError(EvalError.RebindImmutable, run(std.testing.allocator, bad_src));
}

test "program: define-rec builds a cycle" {
    var ctx = try TestCtx.init(
        \\(define-rec self (t self))
        \\self
    );
    defer ctx.deinit();

    const self_id = ctx.env.get("self").?;
    const self_node = ctx.tree.get(self_id);
    try std.testing.expect(self_node.kind == .Stem);
    try std.testing.expectEqual(self_id, self_node.rhs.?);

    const res = ctx.env.get("!result").?;
    try std.testing.expectEqual(self_id, res);
}

test "program: pair builds a fork from two args" {
    var ctx = try TestCtx.init(
        \\(define p (pair leaf leaf))
        \\p
    );
    defer ctx.deinit();

    const leaf_id = ctx.env.get("leaf").?;
    const p_id = ctx.env.get("p").?;
    const node = ctx.tree.get(p_id);
    try std.testing.expect(node.kind == .Fork);
    try std.testing.expectEqual(leaf_id, node.lhs.?);
    try std.testing.expectEqual(leaf_id, node.rhs.?);
}

test "program: first and second project from pair" {
    var ctx = try TestCtx.init(
        \\(define p (pair leaf (pair leaf leaf)))
        \\(define a (first p))
        \\(define b (second p))
        \\(list a b)
    );
    defer ctx.deinit();

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

test "program: self-application shape is a loop" {
    var ctx = try TestCtx.init(
        \\(define-rec loop (pair loop loop))
        \\loop
    );
    defer ctx.deinit();

    const loop_id = ctx.env.get("loop").?;
    const n = ctx.tree.get(loop_id);
    try std.testing.expect(n.kind == .Fork);
    try std.testing.expectEqual(loop_id, n.lhs.?);
    try std.testing.expectEqual(loop_id, n.rhs.?);

    // NOTE: (loop loop) would diverge under unbounded apply
}
