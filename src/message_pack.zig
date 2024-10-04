const std = @import("std");
pub const Value = union(enum) {
    fixmap: u8,
    fixarray: u8,
    fixstr: u8,
    nil: void,
    bool: bool,
    bin: []const u8,
    ext: []const u8,
    float64: f64,
    float32: f32,
    int: union(enum) {
        int8: i8,
        int16: i16,
        int32: i32,
        int64: i64,
    },
    u_int: union(enum) {
        int8: u8,
        int16: u16,
        int32: u32,
        int64: u64,
    },
};

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
        .@"enum" => {
            try writeString(@tagName(val), writer);
        },
        .enum_literal => {
            try writeString(@tagName(val), writer);
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
                try writer.writeFloat(f32, val);
            } else {
                try writer.writeInt(u8, 0xcb, .big);
                try writer.writeFloat(f64, val);
            }
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
            if (val) |v| try encode(@TypeOf(v), v, writer) else try writer.writeInt(u8, 0xC0);
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
};

pub fn decode(comptime T: type, reader: anytype) DecodeMapError!T {
    const tInfo = @typeInfo(T);
    switch (tInfo) {
        .@"struct" => |s| {
            _ = s;
            return try decodeMap(T, reader);
        },
        .bool => {
            const byte = reader.readByte() catch return error.ReadFail;
            switch (byte) {
                0xc3 => return true,
                0xc2 => return false,
                else => return error.TypeFail,
            }
        },
        .int => {
            return decodeInt(T, reader);
        },
        .array => |al| {
            if (al.child == u8) {
                const len = try expectArrayLength(reader);
            } else {
                var result = std.mem.zeroes(T);
                const len = try expectArrayLength(reader);
                const is_optional = @typeInfo(al.child) == .optional;
                if (!is_optional) {
                    if (len != al.len) return error.TypeFail;
                }
                if (len > al.len) return error.TypeFail;
                const iter_len = @min(al.len, len);
                for (0..iter_len) |idx| {
                    result[idx] = try decode(al.child, reader);
                }
                return result;
            }
        },
        else => {
            @compileLog("Unimplemented type", T);
            comptime unreachable;
        },
    }
}

pub fn expectArrayLength(reader: anytype) DecodeMapError!u32 {
    const byte = reader.readByte() catch return error.ReadFail;
    if (@as(u4, @truncate(byte >> 4)) == 0b1001) return @as(u4, @truncate(byte));
    switch (byte) {
        0xdc => {
            return reader.readInt(u16, .big) catch return error.ReadFail;
        },
        0xdd => {
            return reader.readInt(u32, .big) catch return error.ReadFail;
        },
        else => {
            std.log.err("got:{x}", .{byte});
            return error.TypeFail;
        },
    }
}

pub fn decodeInt(comptime T: type, reader: anytype) DecodeMapError!T {
    const typeInfo = @typeInfo(T).int;
    const signedness = typeInfo.signedness;
    const byte = reader.readByte() catch return error.ReadFail;
    if ((byte & 0b10000000) == 0) {
        return @intCast(0x7F & byte);
    } else if (@as(u3, @truncate(byte >> 5)) == 0b111) {
        switch (signedness) {
            .unsigned => return error.TypeFail,
            .signed => {
                const val: T = @intCast(@as(u5, @truncate(byte)));
                return val * -1;
            },
        }
    }
    switch (signedness) {
        .unsigned => {
            switch (byte) {
                0xcc => {
                    return reader.readInt(u8, .big) catch return error.ReadFail;
                },
                0xcd => {
                    if (typeInfo.bits >= 16) {
                        return reader.readInt(u16, .big) catch return error.ReadFail;
                    } else {
                        return error.TypeFail;
                    }
                },
                0xce => {
                    if (typeInfo.bits >= 32) {
                        return reader.readInt(u32, .big) catch return error.ReadFail;
                    } else {
                        return error.TypeFail;
                    }
                },
                0xcf => {
                    if (typeInfo.bits >= 64) {
                        return reader.readInt(u64, .big) catch return error.ReadFail;
                    } else {
                        return error.TypeFail;
                    }
                },
                else => return error.TypeFail,
            }
        },
        .signed => {
            switch (byte) {
                0xd0 => return reader.readInt(i8, .big) catch return error.ReadFail,
                0xd1 => {
                    if (typeInfo.bits >= 16) {
                        return reader.readInt(i16, .big) catch return error.ReadFail;
                    } else {
                        return error.TypeFail;
                    }
                },
                0xd2 => {
                    if (typeInfo.bits >= 32) {
                        return reader.readInt(i32, .big) catch return error.ReadFail;
                    } else {
                        return error.TypeFail;
                    }
                },
                0xd3 => {
                    if (typeInfo.bits >= 64) {
                        return reader.readInt(i64, .big) catch return error.ReadFail;
                    } else {
                        return error.TypeFail;
                    }
                },
                else => return error.TypeFail,
            }
        },
    }
}

fn expectIdentifier(reader: anytype, buffer: []u8) DecodeMapError![]const u8 {
    const byte = reader.readByte() catch return error.ReadFail;

    const len: u32 = if (@as(u3, @truncate(byte >> 5)) == 0b101)
        @as(u5, @truncate(byte))
    else if (byte == 0xd9)
        reader.readInt(u8, .big) catch return error.ReadFail //
    else if (byte == 0xda)
        reader.readInt(u16, .big) catch return error.ReadFail //
    else if (byte == 0xdb)
        reader.readInt(u32, .big) catch return error.ReadFail //
    else
        return error.TypeFail;
    if (len > buffer.len) return error.SizeFail;
    _ = try reader.read(buffer[0..len]);
    return buffer[0..len];
}

fn mapLen(reader: anytype) DecodeMapError!u32 {
    const byte = reader.readByte() catch return error.ReadFail;
    if (@as(u4, @truncate(byte >> 4)) == 0b1000) return @as(u4, @truncate(byte));
    if (byte == 0xde) return reader.readInt(u16, .big) catch return error.ReadFail;
    if (byte == 0xdf) return reader.readInt(u32, .big) catch return error.ReadFail;
    return error.TypeFail;
}

fn decodeMap(comptime T: type, reader: anytype) DecodeMapError!T {
    const tInfo = @typeInfo(T).@"struct";
    var ret: T = undefined;
    const len = try mapLen(reader);
    var nameBuffer: [512]u8 = undefined;
    for (0..len) |idx| {
        _ = idx;
        const field = try expectIdentifier(reader, nameBuffer[0..]);
        std.log.err("field:{s}", .{field});
        inline for (tInfo.fields) |f| {
            if (std.mem.eql(u8, field, f.name)) {
                std.log.err("match:{s}", .{f.name});
                @field(ret, f.name) = try decode(f.type, reader);
            }
        }
    }
    return ret;
}

test {
    const test_struct = struct {
        compact: bool,
        schema: u32,
        list: [4]u8,
    };
    const ts = test_struct{ .compact = true, .schema = 43, .list = [4]u8{ 1, 2, 3, 4 } };
    var al = std.ArrayList(u8).init(std.testing.allocator);
    defer al.deinit();

    try encode(test_struct, ts, al.writer());

    std.log.err("{}", .{std.fmt.fmtSliceEscapeUpper(al.items)});

    var fbs = std.io.fixedBufferStream(al.items);
    const val = try decode(test_struct, fbs.reader());
    std.log.err("{} => {}", .{ val, ts });
}
