const std = @import("std");
const print = std.debug.print;
const panic = std.debug.panic;
const eql = std.mem.eql;
const stdin = std.io.getStdIn();
const ArrayList = std.ArrayList;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var input = ArrayList(u8).init(allocator);
    defer input.deinit();

    // Read input from file argument or stdin
    var args = std.process.args();
    _ = args.next();
    if (args.next()) |filename| {
        if (args.next()) |_| {
            return error.TooManyArguments;
        }

        // Read file
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        try file.reader().readAllArrayList(&input, 100);
    } else {
        // Read line from stdin
        try stdin.reader().streamUntilDelimiter(input.writer(), '\n', null);
    }

    // Parse token tree
    const tree = try TokenTree.fromString(input.items, allocator);
    defer tree.deinit();
    tree.debugPrint(0);

    // Evaluate answer
    const answer = try evaluateTokenTree(tree);
    print("\n\x1b[34m=>\x1b[0m ", .{});
    print("{d}\n", .{answer});
}

test "parse string as tree" {
    const allocator = std.testing.allocator;
    const expect = std.testing.expect;

    const input = "*   ( + 12 3)  \n 81";
    const tree = try TokenTree.fromString(input, allocator);
    defer tree.deinit();

    // * (+ 12 3) 81
    try expect(eql(u8, @tagName(tree), "group"));
    try expect(tree.group.items.len == 3);
    // *
    try expect(eql(u8, @tagName(tree.group.items[0]), "literal"));
    try expect(eql(u8, tree.group.items[0].literal.items, "*"));
    // (+ 12 3)
    try expect(eql(u8, @tagName(tree.group.items[1]), "group"));
    try expect(tree.group.items[1].group.items.len == 3);
    // +
    try expect(eql(u8, @tagName(tree.group.items[1].group.items[0]), "literal"));
    try expect(eql(u8, tree.group.items[1].group.items[0].literal.items, "+"));
    // 12
    try expect(eql(u8, @tagName(tree.group.items[1].group.items[1]), "literal"));
    try expect(eql(u8, tree.group.items[1].group.items[1].literal.items, "12"));
    // 3
    try expect(eql(u8, @tagName(tree.group.items[1].group.items[2]), "literal"));
    try expect(eql(u8, tree.group.items[1].group.items[2].literal.items, "3"));
    // 81
    try expect(eql(u8, @tagName(tree.group.items[2]), "literal"));
    try expect(eql(u8, tree.group.items[2].literal.items, "81"));

    try expect(try evaluateTokenTree(tree) == 1215.0);
}

fn evaluateTokenTree(tree: TokenTree) !f32 {
    switch (tree) {
        .group => |group| {
            if (group.items.len == 0) {
                return error.EmptyGroup;
            }
            if (!eql(u8, @tagName(group.items[0]), "literal")) {
                return error.OperationNotALiteral;
            }
            const operation = group.items[0].literal;

            if (eql(u8, operation.items, "+")) {
                if (group.items.len != 3) {
                    return error.IncorrectArgumentCount;
                }
                const a = try evaluateTokenTree(group.items[1]);
                const b = try evaluateTokenTree(group.items[2]);
                return a + b;
            } else if (eql(u8, operation.items, "*")) {
                if (group.items.len != 3) {
                    return error.IncorrectArgumentCount;
                }
                const a = try evaluateTokenTree(group.items[1]);
                const b = try evaluateTokenTree(group.items[2]);
                return a * b;
            } else {
                return error.UnknownOperation;
            }
        },
        .literal => |lit| {
            const number = try std.fmt.parseFloat(f32, lit.items);
            return number;
        },
    }
}

const Token = union(enum) {
    br_left,
    br_right,
    literal: ArrayList(u8),

    pub fn deinit(self: Token) void {
        switch (self) {
            Token.literal => |lit| lit.deinit(),
            else => {},
        }
    }

    pub fn format(
        self: Token,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            Token.literal => |lit| try writer.print("{s}", .{lit.items}),
            Token.br_left => try writer.writeAll("("),
            Token.br_right => try writer.writeAll(")"),
        }
    }
};

fn lexTokens(input: []const u8, allocator: anytype) !ArrayList(Token) {
    var tokens = ArrayList(Token).init(allocator);
    var current_token = ArrayList(u8).init(allocator);

    for (input) |char| {
        switch (char) {
            ' ', '(', ')' => {
                if (current_token.items.len > 0) {
                    try tokens.append(Token{ .literal = current_token });
                    current_token = ArrayList(u8).init(allocator);
                }
            },
            else => {},
        }

        switch (char) {
            '\n' => {},
            ' ' => {},
            '(' => {
                try tokens.append(Token.br_left);
            },
            ')' => {
                try tokens.append(Token.br_right);
            },
            else => try current_token.append(char),
        }
    }
    if (current_token.items.len > 0) {
        try tokens.append(Token{ .literal = current_token });
    }

    return tokens;
}

const TokenTree = union(enum) {
    group: ArrayList(TokenTree),
    literal: ArrayList(u8),

    fn deinit(self: TokenTree) void {
        switch (self) {
            .group => |array| {
                for (array.items) |item| {
                    item.deinit();
                }
                array.deinit();
            },
            .literal => |lit| lit.deinit(),
        }
    }

    fn debugPrint(self: TokenTree, indent: usize) void {
        switch (self) {
            .group => |array| {
                for (0..indent) |_| {
                    print("    ", .{});
                }
                print("\x1b[33m", .{});
                print("(\n", .{});
                print("\x1b[0m", .{});
                for (array.items) |item| {
                    debugPrint(item, indent + 1);
                }
                for (0..indent) |_| {
                    print("    ", .{});
                }
                print("\x1b[33m", .{});
                print(")\n", .{});
                print("\x1b[0m", .{});
            },
            .literal => |lit| {
                for (0..indent) |_| {
                    print("    ", .{});
                }
                print("{s}\n", .{lit.items});
            },
        }
    }

    fn fromString(reader: anytype, allocator: anytype) !TokenTree {
        var tokens = try lexTokens(reader, allocator);
        defer tokens.deinit();
        defer for (tokens.items) |token| {
            token.deinit();
        };

        var index: usize = 0;
        return TokenTree.fromTokens(&tokens, &index, 0, allocator);
    }

    fn fromTokens(tokens: *ArrayList(Token), index: *usize, depth: usize, allocator: anytype) !TokenTree {
        if (tokens.items.len == 0) {
            return error.NoTokens;
        }
        if (tokens.items.len == 1) {
            const token = tokens.items[0];
            switch (token) {
                .literal => |lit| {
                    return TokenTree{ .literal = lit };
                },
                else => return error.SingleBracket,
            }
        }

        var group = ArrayList(TokenTree).init(allocator);

        while (index.* < tokens.items.len) {
            const token = tokens.items[index.*];
            index.* += 1;

            switch (token) {
                .literal => |lit| {
                    var literal = ArrayList(u8).init(allocator);
                    try literal.appendSlice(lit.items);
                    try group.append(TokenTree{ .literal = literal });
                },
                .br_left => {
                    const subgroup = try TokenTree.fromTokens(tokens, index, depth + 1, allocator);
                    try group.append(subgroup);
                },
                .br_right => {
                    if (depth == 0) {
                        return error.UnexpectedRightBracket;
                    }
                    return TokenTree{ .group = group };
                },
            }
        }

        if (depth > 0) {
            return error.UnexpectedEndOfStream;
        }

        return TokenTree{ .group = group };
    }
};
