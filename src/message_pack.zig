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
        .array => {},
        .pointer => {},
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

test {
    const test_struct = struct {
        compact: bool,
        schema: u32,
    };
    const ts = test_struct{ .compact = true, .schema = 0 };
    var al = std.ArrayList(u8).init(std.testing.allocator);
    defer al.deinit();

    try encode(test_struct, ts, al.writer());

    std.log.err("{}", .{std.fmt.fmtSliceEscapeUpper(al.items)});
}
