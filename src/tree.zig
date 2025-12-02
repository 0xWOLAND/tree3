const std = @import("std");

pub const Id = u32;

pub const Node = struct {
    pub const Kind = enum { Leaf, Stem, Fork };

    kind: Kind,
    lhs: ?Id,
    rhs: ?Id,

    pub fn leaf() Node {
        return .{ .kind = .Leaf, .lhs = null, .rhs = null };
    }
    pub fn stem(a: Id) Node {
        return .{ .kind = .Stem, .lhs = null, .rhs = a };
    }
    pub fn fork(a: Id, b: Id) Node {
        return .{ .kind = .Fork, .lhs = a, .rhs = b };
    }
};

pub const Tree = struct {
    alloc: std.mem.Allocator,

    nodes: std.ArrayListUnmanaged(Node),

    pub fn init(parent: std.mem.Allocator) !Tree {
        return .{
            .alloc = parent,
            .nodes = .{},
        };
    }

    pub fn deinit(self: *Tree) void {
        self.nodes.deinit(self.alloc);
    }

    pub fn insert(self: *Tree, n: Node) !Id {
        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.append(self.alloc, n);
        return id;
    }

    pub fn reserve(self: *Tree) !Id {
        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.append(self.alloc, Node.leaf());
        return id;
    }

    pub fn set(self: *Tree, id: Id, n: Node) void {
        self.nodes.items[id] = n;
    }

    pub inline fn get(self: *Tree, id: Id) Node {
        return self.nodes.items[id];
    }

    pub fn apply(self: *Tree, a0: Id, b0: Id) !Id {
        var a = a0;
        var b = b0;

        while (true) {
            const an = self.get(a);

            switch (an.kind) {
                .Leaf => return try self.insert(Node.stem(b)),

                .Stem => return try self.insert(Node.fork(an.rhs.?, b)),

                .Fork => {
                    const left = self.get(an.lhs.?);

                    switch (left.kind) {
                        .Leaf => return an.rhs.?,

                        .Stem => {
                            a = left.rhs.?;
                            continue;
                        },

                        .Fork => {
                            const bnode = self.get(b);
                            switch (bnode.kind) {
                                .Leaf => return left.lhs.?,

                                .Stem => {
                                    a = left.rhs.?;
                                    b = bnode.rhs.?;
                                    continue;
                                },

                                .Fork => {
                                    a = an.rhs.?;
                                    b = bnode.lhs.?;
                                },
                            }
                        },
                    }
                },
            }
        }
    }
};
