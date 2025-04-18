const std = @import("std");

fn writeString(data: []const u8, writer: anytype) !void {
    if (data.len < 31) {
        try writer.writeInt(u8, 0b10100000 | @as(u8, @truncate(data.len)), .big);
    } else if (data.len < 255) {
        try writer.writeInt(u8, 0xd9, .big);
        try writer.writeInt(u8, @truncate(data.len), .big);
    } else if (data.len < 65535) {
        try writer.writeInt(u8, 0xda, .big);
        try writer.writeInt(u16, @truncate(data.len), .big);
    } else {
        try writer.writeInt(u8, 0xdb, .big);
        try writer.writeInt(u32, @truncate(data.len), .big);
    }
    _ = try writer.write(data);
}

fn writeArray(comptime T: type, val: []const T, writer: anytype) !void {
    if (val.len <= 15) {
        try writer.writeInt(u8, 0b10010000 | @as(u8, @truncate(val.len)), .big);
    } else if (val.len <= 65535) {
        try writer.writeInt(u8, 0xdc, .big);
        try writer.writeInt(u16, @truncate(val.len), .big);
    } else {
        try writer.writeInt(u8, 0xdd, .big);
        try writer.writeInt(u32, @truncate(val.len), .big);
    }
    for (val) |v| {
        try encode(T, v, writer);
    }
}

fn writeBin(val: []const u8, writer: anytype) !void {
    if (val.len <= 255) {
        try writer.writeInt(u8, 0xc4, .big);
        try writer.writeInt(u8, @truncate(val.len), .big);
    } else if (val.len <= 65535) {
        try writer.writeInt(u8, 0xc5, .big);
        try writer.writeInt(u16, @truncate(val.len), .big);
    } else {
        try writer.writeInt(u8, 0xc5, .big);
        try writer.writeInt(u32, @truncate(val.len), .big);
    }
    _ = try writer.write(val);
}

pub fn encode(comptime T: type, val: T, writer: anytype) !void {
    const info = @typeInfo(T);
    switch (info) {
        .@"struct" => |s| {
            if (s.fields.len <= 15) {
                try writer.writeInt(u8, 0b10000000 | @as(u8, @truncate(s.fields.len)), .big);
            } else if (s.fields.len <= (65535)) {
                try writer.writeInt(u8, 0xde, .big);
                try writer.writeInt(u16, @truncate(s.fields.len), .big);
            } else {
                try writer.writeInt(u8, 0xdf, .big);
                try writer.writeInt(u32, @truncate(s.fields.len), .big);
            }

            inline for (s.fields) |f| {
                try writeString(f.name, writer);
                try encode(f.type, @field(val, f.name), writer);
            }
        },
        .int => |i| {
            switch (i.signedness) {
                .signed => {
                    if (val > 0 and val <= 0x7F) {
                        try writer.write(val);
                    } else if (val < 0 and val > -31) {
                        try writer.write(0b11100000 | @abs(val));
                    } else {
                        if (i.bits <= 8) {
                            try writer.writeInt(u8, 0xd0, .big);
                            try writer.writeInt(i8, val, .big);
                        } else if (i.bits <= 16) {
                            try writer.writeInt(u8, 0xd1, .big);
                            try writer.writeInt(i16, val, .big);
                        } else if (i.bits <= 32) {
                            try writer.writeInt(u8, 0xd2, .big);
                            try writer.writeInt(i32, val, .big);
                        } else if (i.bits <= 64) {
                            try writer.writeInt(u8, 0xd3, .big);
                            try writer.writeInt(i64, val, .big);
                        } else {
                            unreachable; // not sure what to do about > 64 bits
                        }
                    }
                },
                .unsigned => {
                    if (val <= 0x7F) {
                        try writer.writeInt(u8, @truncate(val), .big);
                    } else {
                        if (i.bits <= 8) {
                            try writer.writeInt(u8, @truncate(val), .big);
                        } else if (i.bits <= 8) {
                            try writer.writeInt(u8, 0xcc, .big);
                            try writer.writeInt(u8, val, .big);
                        } else if (i.bits <= 16) {
                            try writer.writeInt(u8, 0xcd, .big);
                            try writer.writeInt(u16, val, .big);
                        } else if (i.bits <= 32) {
                            try writer.writeInt(u8, 0xce, .big);
                            try writer.writeInt(u32, val, .big);
                        } else if (i.bits <= 64) {
                            try writer.writeInt(u8, 0xcf, .big);
                            try writer.writeInt(u64, val, .big);
                        } else {
                            unreachable; // not sure what to do about > 64 bits
                        }
                    }
                },
            }
            //
        },
        .comptime_int => {
            const ints = []type{ u8, i8, u16, i16, u32, i32, u64, i64 };
            inline for (ints) |t| {
                if (val >= std.math.minInt(t) and val <= std.math.maxInt(t)) {
                    try encode(t, val, writer);
                    break;
                }
            }
        },
        .@"enum" => |e| {
            try encode(e.tag_type, @intFromEnum(val), writer);
        },
        .enum_literal => {
            unreachable; //TODO
        },
        .@"union" => {
            unreachable; //TODO
        },
        .bool => {
            if (val) {
                try writer.writeInt(u8, 0xc3, .big);
            } else {
                try writer.writeInt(u8, 0xc2, .big);
            }
        },
        .comptime_float => {
            //treat comptime_float's as f64's
            try writer.writeInt(u8, 0xcb, .big);
            try writer.writeFloat(f64, val);
        },
        .float => |f| {
            if (f.bits == 32) {
                try writer.writeInt(u8, 0xca, .big);
            } else if (f.bits == 64) {
                try writer.writeInt(u8, 0xcb, .big);
            } else {
                unreachable;
            }
            const bytes = std.mem.toBytes(val);
            _ = try writer.write(bytes[0..]);
        },
        .array => |a_info| {
            if (a_info.child == u8) {
                try writeBin(val[0..], writer);
            } else {
                try writeArray(a_info.child, val[0..], writer);
            }
        },
        .pointer => |p_info| {
            if (p_info.child == u8) {
                try writeBin(val[0..], writer);
            } else {
                try writeArray(p_info.child, val[0..], writer);
            }
        },
        .null => {
            try writer.writeInt(u8, 0xc0);
        },
        .optional => {
            if (val) |v| try encode(@TypeOf(v), v, writer) else try writer.writeInt(u8, 0xC0, .big);
        },

        .type, .void, .noreturn, .@"fn", .frame, .@"anyframe", .@"opaque", .error_union, .error_set, .undefined => unreachable,
        .vector => unreachable, //TODO
        //else => {},
    }
    //
}

const DecodeMapError = error{
    ReadFail,
    TypeFail,
    SizeFail,
    TokenError,
    InvalidTokenType,
    IntegerError,
    FailOver, //TODO remove
};

pub fn decode(comptime T: type, tokens: *MessagePackIter) DecodeMapError!T {
    const tInfo = @typeInfo(T);
    switch (tInfo) {
        //.@"struct" => |s| {},
        .bool => {
            if (tokens.next() catch return error.TokenError) |val| {
                switch (val) {
                    .bool => |b| return b,
                    else => return error.InvalidTokenType,
                }
                return error.MissingToken;
            }
        },
        .int => |i| {
            if (tokens.next() catch return error.TokenError) |val| {
                switch (i.signedness) {
                    .unsigned => {
                        const max: u64 = std.math.maxInt(T);
                        const value: u64 = switch (val) {
                            .int => |i_v| if (i_v > 0 and i_v < max) @intCast(i_v) else return error.IntegerError,
                            .u_int => |u_v| if (u_v < max) u_v else return error.IntegerError,
                            else => return error.InvalidTokenType,
                        };
                        return @intCast(value);
                    },
                    .signed => {},
                }

                return error.MissingToken;
            }
        },
        .@"union" => {},
        .vector => {},
        .type, .void, .noreturn, .comptime_float, .comptime_int, .undefined, .error_union, .error_set, .@"fn", .@"opaque", .frame, .@"anyframe", .null => {
            @compileLog("Unimplemented type", T);
            comptime unreachable;
        },
        else => return error.TODO,
    }
    return error.FailOver;
}

test {
    {
        const data = "\x44";
        errdefer std.log.err("{}", .{std.fmt.fmtSliceEscapeUpper(data)});
        var iter = MessagePackIter{ .data = data };
        const value = try decode(u32, &iter);
        try std.testing.expectEqual(@as(u32, 0x44), value);
    }
    {
        const data = "\xc2";
        errdefer std.log.err("{}", .{std.fmt.fmtSliceEscapeUpper(data)});
        var iter = MessagePackIter{ .data = data };
        const value = try decode(bool, &iter);
        try std.testing.expectEqual(@as(bool, false), value);
    }
}

const MessagePackIter = struct {
    data: []const u8,
    idx: usize = 0,
    pub const Token = union(enum) {
        map: u32,
        array: u32,
        bin: []const u8,
        int: i64,
        u_int: u64,
        bool: bool,
        nil: void,
        str: []const u8,
        ext: struct { type: u8, data: []const u8 },
        f32: f32,
        f64: f64,
    };
    fn nextByte(self: *MessagePackIter) ?u8 {
        if (self.idx >= self.data.len) return null;
        defer self.idx += 1;
        return self.data[self.idx];
    }
    fn getSlice(self: *MessagePackIter, len: usize) ![]const u8 {
        if (self.idx + len >= self.data.len) return error.TooLong;
        defer self.idx += len;
        return self.data[self.idx..][0..len];
    }
    fn readInt(self: *MessagePackIter, comptime T: type) !T {
        return std.mem.readVarInt(T, try self.getSlice(@sizeOf(T)), .big);
    }
    fn readIntToken(self: *MessagePackIter, comptime T: type) !Token {
        const int_info = @typeInfo(T).int;
        switch (int_info.signedness) {
            .unsigned => return .{ .u_int = std.mem.readVarInt(T, try self.getSlice(@sizeOf(T)), .big) },
            .signed => return .{ .int = std.mem.readVarInt(T, try self.getSlice(@sizeOf(T)), .big) },
        }
    }
    fn readFloat(self: *MessagePackIter, comptime T: type) !T {
        const data = try self.getSlice(@sizeOf(T));
        var d: T = 0;
        var ptr: [*]u8 = @ptrCast(&d);
        for (data, 0..) |b, idx| ptr[idx] = b;
        switch (@import("builtin").cpu.arch.endian()) {
            .little => {
                for (data, 0..) |b, idx| ptr[@sizeOf(T) - idx - 1] = b;
            },
            .big => {
                for (data, 0..) |b, idx| ptr[idx] = b;
            },
        }
        return d;
    }
    pub fn next(self: *MessagePackIter) !?Token {
        const byte = self.nextByte() orelse return null;
        switch (byte) {
            0x00...0x7f => return .{ .u_int = byte }, //positive fixint

            0x80...0x8f => return .{ .map = @as(u4, @truncate(byte)) }, //fixmap
            0x90...0x9f => return .{ .array = @as(u4, @truncate(byte)) }, //fixarray
            0xa0...0xbf => return .{ .str = try self.getSlice(@as(u5, @truncate(byte))) }, //fixstr
            0xc0 => return .nil,
            0xc1 => return error.UnustedToken,
            0xc2 => return .{ .bool = false },
            0xc3 => return .{ .bool = true },
            0xc4 => return .{ .bin = try self.getSlice(try self.readInt(u8)) },
            0xc5 => return .{ .bin = try self.getSlice(try self.readInt(u16)) },
            0xc6 => return .{ .bin = try self.getSlice(try self.readInt(u32)) },
            0xc7 => {
                const len = try self.readInt(u8);
                return .{
                    .ext = .{
                        .type = self.nextByte() orelse return error.TooLong,
                        .data = try self.getSlice(len),
                    },
                };
            },
            0xc8 => {
                const len = try self.readInt(u16);
                return .{
                    .ext = .{
                        .type = self.nextByte() orelse return error.TooLong,
                        .data = try self.getSlice(len),
                    },
                };
            },
            0xc9 => {
                const len = try self.readInt(u32);
                return .{
                    .ext = .{
                        .type = self.nextByte() orelse return error.TooLong,
                        .data = try self.getSlice(len),
                    },
                };
            },
            0xca => {
                return .{ .f32 = try self.readFloat(f32) };
            }, //f32
            0xcb => {
                return .{ .f64 = try self.readFloat(f64) };
            }, //f64
            0xcc => return try self.readIntToken(u8),
            0xcd => return try self.readIntToken(u16),
            0xce => return try self.readIntToken(u32),
            0xcf => return try self.readIntToken(u64),
            0xd0 => return try self.readIntToken(i8),
            0xd1 => return try self.readIntToken(i16),
            0xd2 => return try self.readIntToken(i32),
            0xd3 => return try self.readIntToken(i64),
            0xd4 => {
                return .{
                    .ext = .{
                        .type = self.nextByte() orelse return error.TooLong,
                        .data = try self.getSlice(1),
                    },
                };
            }, //fixext1
            0xd5 => {
                return .{
                    .ext = .{
                        .type = self.nextByte() orelse return error.TooLong,
                        .data = try self.getSlice(2),
                    },
                };
            }, //fixext2
            0xd6 => {
                return .{
                    .ext = .{
                        .type = self.nextByte() orelse return error.TooLong,
                        .data = try self.getSlice(4),
                    },
                };
            }, //fixext4
            0xd7 => {
                return .{
                    .ext = .{
                        .type = self.nextByte() orelse return error.TooLong,
                        .data = try self.getSlice(8),
                    },
                };
            }, //fixext8
            0xd8 => {
                return .{
                    .ext = .{
                        .type = self.nextByte() orelse return error.TooLong,
                        .data = try self.getSlice(16),
                    },
                };
            }, //fixext16
            0xd9 => return .{ .str = try self.getSlice(try self.readInt(u8)) },
            0xda => return .{ .str = try self.getSlice(try self.readInt(u16)) },
            0xdb => return .{ .str = try self.getSlice(try self.readInt(u32)) },
            0xdc => return .{ .array = try self.readInt(u16) },
            0xdd => return .{ .array = try self.readInt(u32) },
            0xde => return .{ .map = try self.readInt(u16) },
            0xdf => return .{ .map = try self.readInt(u32) },
            0xe0...0xff => {
                const val: u5 = @truncate(byte);
                return .{ .int = 0 - val };
            },
        }
    }
};

test {
    const tc = struct {
        encoded: []const u8,
        tokens: []const MessagePackIter.Token,
    };
    const tests = [_]tc{
        .{
            .encoded = "\x82\xA7compact\xc3\xa6schema\x00",
            .tokens = &.{
                .{ .map = 2 },
                .{ .str = "compact" },
                .{ .bool = true },
                .{ .str = "schema" },
                .{ .u_int = 0 },
            },
        },
    };
    for (tests) |t| {
        var iter = MessagePackIter{ .data = t.encoded };
        var idx: usize = 0;
        while (try iter.next()) |n| {
            errdefer std.log.err("{}", .{n});
            defer idx += 1;
            try std.testing.expectEqualDeep(t.tokens[idx], n);
        }
    }
}
