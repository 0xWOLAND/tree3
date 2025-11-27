const std = @import("std");

pub const Id = u32;

pub const Node = struct {
    lhs: ?Id,
    rhs: ?Id,

    pub fn leaf() Node {
        return .{ .lhs = null, .rhs = null };
    }

    pub fn stem(a: Id) Node {
        return .{ .lhs = null, .rhs = a };
    }

    pub fn fork(a: Id, b: Id) Node {
        return .{ .lhs = a, .rhs = b };
    }
};

pub const Trees = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(Node),
    table: std.AutoHashMap(Node, Id),

    pub fn init(allocator: std.mem.Allocator) !Trees {
        return .{
            .allocator = allocator,
            .nodes = .{},
            .table = std.AutoHashMap(Node, Id).init(allocator),
        };
    }

    pub fn deinit(self: *Trees) void {
        self.nodes.deinit(self.allocator);
        self.table.deinit();
    }

    pub fn insert(self: *Trees, n: Node) !Id {
        if (self.table.get(n)) |idx| return idx;

        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, n);
        try self.table.put(n, id);
        return id;
    }

    pub inline fn get(self: *Trees, id: Id) Node {
        return self.nodes.items[id];
    }

    /// Simple branch-first evaluator
    pub fn apply(self: *Trees, a0: Id, b0: Id) !Id {
        var a = a0;
        var b = b0;

        while (true) {
            const an = self.get(a);

            // △ b → △ b
            if (an.lhs == null and an.rhs == null)
                return try self.insert(Node.stem(b));

            // △ a b → △ a b
            if (an.lhs == null and an.rhs != null)
                return try self.insert(Node.fork(an.rhs.?, b));

            // fork-case: inspect left
            const left = self.get(an.lhs.?);

            // △ △ a b = a
            if (left.lhs == null and left.rhs == null)
                return an.rhs.?;

            // △ (△ x) y b = x b (y b)
            if (left.lhs == null and left.rhs != null) {
                a = left.rhs.?;
                continue;
            }

            // △ (△ x y) z w cases
            const bnode = self.get(b);

            if (bnode.lhs == null and bnode.rhs == null)
                return left.lhs.?;

            if (bnode.lhs == null and bnode.rhs != null) {
                a = left.rhs.?;
                b = bnode.rhs.?;
                continue;
            }

            // fork/fork
            a = an.rhs.?;
            b = bnode.lhs.?;
        }
    }
};
