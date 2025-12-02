const std = @import("std");
const Tree = @import("tree.zig").Tree;
const Node = @import("tree.zig").Node;
const Id = @import("tree.zig").Id;
const Env = @import("eval.zig").Env;

const Base = struct { leaf: Id, k: Id, i: Id, f: Id };

fn base(t: *Tree) !Base {
    const leaf_id = try t.insert(Node.leaf());
    const k_id = try t.insert(Node.stem(leaf_id));

    const pair = try t.insert(Node.fork(leaf_id, leaf_id));
    const i_id = try t.insert(Node.fork(pair, k_id));
    const f_id = try t.insert(Node.fork(leaf_id, i_id));

    return .{ .leaf = leaf_id, .k = k_id, .i = i_id, .f = f_id };
}

fn boolAnd(c: Base, p: Id, q: Id) Id {
    return if (p == c.k and q == c.k) c.k else c.f;
}

fn boolOr(c: Base, p: Id, q: Id) Id {
    return if (p == c.k or q == c.k) c.k else c.f;
}

fn boolNot(c: Base, p: Id) Id {
    return if (p == c.k) c.f else c.k;
}

fn boolImplies(c: Base, p: Id, q: Id) Id {
    return boolOr(c, boolNot(c, p), q);
}

fn boolIff(c: Base, p: Id, q: Id) Id {
    return if (p == q) c.k else c.f;
}

pub fn init(env: *Env, t: *Tree) !void {
    const c = try base(t);
    try env.put("true", c.k);
    try env.put("K", c.k);
    try env.put("false", c.f);
    try env.put("id", c.i);
}

test "core booleans behave" {
    var t = try Tree.init(std.testing.allocator);
    defer t.deinit();

    const c = try base(&t);
    const x = try t.insert(Node.stem(c.k));
    const y = c.leaf;

    const res_k = try t.apply(try t.apply(c.k, x), y);
    try std.testing.expect(std.meta.eql(t.get(res_k), t.get(x)));

    const res_f = try t.apply(try t.apply(c.f, x), y);
    try std.testing.expect(std.meta.eql(t.get(res_f), t.get(y)));

    const res_i = try t.apply(c.i, x);
    try std.testing.expect(std.meta.eql(t.get(res_i), t.get(x)));
}

test "boolean operators match truth tables" {
    var t = try Tree.init(std.testing.allocator);
    defer t.deinit();

    const c = try base(&t);
    const pairs = [_][2]Id{
        .{ c.k, c.k },
        .{ c.k, c.f },
        .{ c.f, c.k },
        .{ c.f, c.f },
    };

    for (pairs) |pq| {
        const p = pq[0];
        const q = pq[1];
        try std.testing.expect(boolAnd(c, p, q) == (if (p == c.k and q == c.k) c.k else c.f));
        try std.testing.expect(boolOr(c, p, q) == (if (p == c.k or q == c.k) c.k else c.f));
        try std.testing.expect(boolImplies(c, p, q) == (if (p == c.k and q == c.f) c.f else c.k));
        try std.testing.expect(boolIff(c, p, q) == (if (p == q) c.k else c.f));
        try std.testing.expect(boolNot(c, p) == (if (p == c.k) c.f else c.k));
    }
}
