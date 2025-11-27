const std = @import("std");
const expect = std.testing.expect;

const Trees = @import("tree.zig").Trees;
const Node = @import("tree.zig").Node;
const Id = @import("tree.zig").Id;

test "basic tree calculus apply" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var T = try Trees.init(alloc);
    defer T.deinit();

    const leaf = try T.insert(Node.leaf());
    const stem_leaf = try T.insert(Node.stem(leaf));
    const fork_ll = try T.insert(Node.fork(leaf, leaf));

    // Identity-like behavior:
    // △ (△ △ △) △   → △
    const id = try T.insert(Node.fork(fork_ll, leaf));

    // apply id △ = △
    const r1 = try T.apply(id, leaf);
    try expect(r1 == leaf);

    // apply △ x = △ x  (stem)
    const r2 = try T.apply(leaf, leaf);
    const expected2 = try T.insert(Node.stem(leaf));
    try expect(r2 == expected2);

    // apply (△ a) b = △ a b
    const some_a = leaf;
    const some_b = stem_leaf;
    const stemA = try T.insert(Node.stem(some_a));
    const r3 = try T.apply(stemA, some_b);
    const expected3 = try T.insert(Node.fork(some_a, some_b));
    try expect(r3 == expected3);
}
