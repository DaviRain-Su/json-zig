const std = @import("std");
const testing = std.testing;

pub const ParseError = error{
    InvalidJson,
    ExpectedCommaOrClosingBracket,
    ExpectedStringKey,
    ExpectedColon,
    ExpectedCommaOrClosingBrace,
    OutOfMemory,
    InvalidCharacter,
};

pub const JsonType = enum {
    Null,
    Bool,
    Number,
    String,
    Array,
    Object,
};

pub const JsonValue = union(JsonType) {
    Null: void,
    Bool: bool,
    Number: f64,
    String: []const u8,
    Array: []JsonValue,
    Object: std.StringArrayHashMap(JsonValue),

    pub fn deinit(self: *JsonValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Array => |items| {
                for (items) |*item| {
                    item.deinit(allocator);
                }
                allocator.free(items);
            },
            .Object => |*map| {
                var it = map.iterator();
                while (it.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                map.deinit();
            },
            else => {},
        }
    }

    pub fn parse(allocator: std.mem.Allocator, input: []const u8) ParseError!JsonValue {
        const lexer = Lexer.init(input);
        var parser = Parser.init(allocator, lexer);
        return parser.parseJson();
    }
};

const Parser = struct {
    lexer: Lexer,
    cur_token: Token,
    peek_token: Token,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, lexer: Lexer) Parser {
        var p = Parser{
            .lexer = lexer,
            .allocator = allocator,
            .cur_token = undefined,
            .peek_token = undefined,
        };
        p.nextToken();
        p.nextToken();
        return p;
    }

    fn nextToken(self: *Parser) void {
        self.cur_token = self.peek_token;
        self.peek_token = self.lexer.nextToken();
    }

    fn parseJson(self: *Parser) ParseError!JsonValue {
        const val = try self.parseValue();
        // In a strict parser, we might check for EOF here.
        return val;
    }

    fn parseValue(self: *Parser) ParseError!JsonValue {
        switch (self.cur_token.type) {
            .LBrace => return self.parseObject(),
            .LBracket => return self.parseArray(),
            .String => return JsonValue{ .String = self.cur_token.literal },
            .Number => {
                const num = std.fmt.parseFloat(f64, self.cur_token.literal) catch return error.InvalidCharacter;
                return JsonValue{ .Number = num };
            },
            .True => return JsonValue{ .Bool = true },
            .False => return JsonValue{ .Bool = false },
            .Null => return JsonValue{ .Null = {} },
            else => return error.InvalidJson,
        }
    }

    fn parseArray(self: *Parser) ParseError!JsonValue {
        const List = std.ArrayList(JsonValue);
        var list = List.initCapacity(self.allocator, 0) catch return error.OutOfMemory;
        errdefer {
            for (list.items) |*item| item.deinit(self.allocator);
            list.deinit(self.allocator);
        }

        // cur_token is '['
        if (self.peek_token.type == .RBracket) {
            self.nextToken(); // consume '['
            return JsonValue{ .Array = try list.toOwnedSlice(self.allocator) };
        }

        self.nextToken(); // move to first element

        while (true) {
            const val = try self.parseValue();
            try list.append(self.allocator, val);

            if (self.peek_token.type == .RBracket) {
                break;
            }

            if (self.peek_token.type != .Comma) {
                return error.ExpectedCommaOrClosingBracket;
            }

            self.nextToken(); // consume ','
            self.nextToken(); // move to next element
        }

        self.nextToken(); // consume ']'

        return JsonValue{ .Array = try list.toOwnedSlice(self.allocator) };
    }

    fn parseObject(self: *Parser) ParseError!JsonValue {
        const Map = std.StringArrayHashMap(JsonValue);
        var map = Map.init(self.allocator);
        errdefer {
            var it = map.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            map.deinit();
        }

        // cur_token is '{'
        if (self.peek_token.type == .RBrace) {
            self.nextToken(); // consume '}'
            return JsonValue{ .Object = map };
        }

        self.nextToken(); // move to first key

        while (true) {
            if (self.cur_token.type != .String) {
                return error.ExpectedStringKey;
            }
            const key = self.cur_token.literal;

            if (self.peek_token.type != .Colon) {
                return error.ExpectedColon;
            }

            self.nextToken(); // consume key, now at ':'
            self.nextToken(); // consume ':', now at value

            const val = try self.parseValue();
            try map.put(key, val);

            if (self.peek_token.type == .RBrace) {
                break;
            }

            if (self.peek_token.type != .Comma) {
                return error.ExpectedCommaOrClosingBrace;
            }

            self.nextToken(); // consume ','
            self.nextToken(); // move to next key
        }

        self.nextToken(); // consume '}'

        return JsonValue{ .Object = map };
    }
};

pub const TokenType = enum {
    Illegal,
    EOF,
    LBrace, // {
    RBrace, // }
    LBracket, // [
    RBracket, // ]
    Colon, // :
    Comma, // ,
    String,
    Number,
    True,
    False,
    Null,
};

pub const Token = struct {
    type: TokenType,
    literal: []const u8,
};

pub const Lexer = struct {
    input: []const u8,
    position: usize = 0,
    read_position: usize = 0,
    ch: u8 = 0,

    pub fn init(input: []const u8) Lexer {
        var lexer = Lexer{ .input = input };
        lexer.readChar();
        return lexer;
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespace();

        const tok: Token = switch (self.ch) {
            '{' => .{ .type = .LBrace, .literal = "{" },
            '}' => .{ .type = .RBrace, .literal = "}" },
            '[' => .{ .type = .LBracket, .literal = "[" },
            ']' => .{ .type = .RBracket, .literal = "]" },
            ':' => .{ .type = .Colon, .literal = ":" },
            ',' => .{ .type = .Comma, .literal = "," },
            '"' => return self.readString(),
            0 => .{ .type = .EOF, .literal = "" },
            else => blk: {
                if (isLetter(self.ch)) {
                    const ident = self.readIdentifier();
                    break :blk Token{ .type = lookupIdent(ident), .literal = ident };
                } else if (isDigit(self.ch) or self.ch == '-') {
                    const number = self.readNumber();
                    break :blk Token{ .type = .Number, .literal = number };
                } else {
                    break :blk Token{ .type = .Illegal, .literal = "" };
                }
            },
        };

        if (tok.type != .String and tok.type != .Number and tok.type != .True and tok.type != .False and tok.type != .Null and tok.type != .Illegal) {
            self.readChar();
        } else if (tok.type == .Illegal) {
            self.readChar();
        }

        return tok;
    }

    fn readChar(self: *Lexer) void {
        if (self.read_position >= self.input.len) {
            self.ch = 0;
        } else {
            self.ch = self.input[self.read_position];
        }
        self.position = self.read_position;
        self.read_position += 1;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.ch == ' ' or self.ch == '\t' or self.ch == '\n' or self.ch == '\r') {
            self.readChar();
        }
    }

    fn readIdentifier(self: *Lexer) []const u8 {
        const position = self.position;
        while (isLetter(self.ch)) {
            self.readChar();
        }
        return self.input[position..self.position];
    }

    fn readNumber(self: *Lexer) []const u8 {
        const position = self.position;
        if (self.ch == '-') {
            self.readChar();
        }
        while (isDigit(self.ch)) {
            self.readChar();
        }
        if (self.ch == '.') {
            self.readChar();
            while (isDigit(self.ch)) {
                self.readChar();
            }
        }
        if (self.ch == 'e' or self.ch == 'E') {
            self.readChar();
            if (self.ch == '+' or self.ch == '-') {
                self.readChar();
            }
            while (isDigit(self.ch)) {
                self.readChar();
            }
        }
        return self.input[position..self.position];
    }

    fn readString(self: *Lexer) Token {
        const position = self.position + 1;
        while (true) {
            self.readChar();
            if (self.ch == '"' or self.ch == 0) {
                break;
            }
            if (self.ch == '\\') {
                self.readChar();
            }
        }
        const literal = self.input[position..self.position];
        self.readChar();
        return Token{ .type = .String, .literal = literal };
    }
};

fn isLetter(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_';
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn lookupIdent(ident: []const u8) TokenType {
    if (std.mem.eql(u8, ident, "true")) return .True;
    if (std.mem.eql(u8, ident, "false")) return .False;
    if (std.mem.eql(u8, ident, "null")) return .Null;
    return .Illegal;
}

test "Lexer test" {
    const input =
        "{\n" ++
        "  \"key\": \"value\",\n" ++
        "  \"number\": 123.45,\n" ++
        "  \"bool\": true,\n" ++
        "  \"null_val\": null,\n" ++
        "  \"array\": [1, 2, 3]\n" ++
        "}";

    var lexer = Lexer.init(input);

    const expected_tokens = [_]TokenType{
        .LBrace,
        .String,
        .Colon,
        .String,
        .Comma,
        .String,
        .Colon,
        .Number,
        .Comma,
        .String,
        .Colon,
        .True,
        .Comma,
        .String,
        .Colon,
        .Null,
        .Comma,
        .String,
        .Colon,
        .LBracket,
        .Number,
        .Comma,
        .Number,
        .Comma,
        .Number,
        .RBracket,
        .RBrace,
        .EOF,
    };

    for (expected_tokens) |expected_type| {
        const tok = lexer.nextToken();
        try testing.expectEqual(expected_type, tok.type);
    }
}

test "Parser test" {
    const input =
        "{\n" ++
        "  \"key\": \"value\",\n" ++
        "  \"number\": 123.45,\n" ++
        "  \"bool\": true,\n" ++
        "  \"null_val\": null,\n" ++
        "  \"array\": [1, 2, 3]\n" ++
        "}";

    var val = try JsonValue.parse(std.testing.allocator, input);
    defer val.deinit(std.testing.allocator);

    try testing.expect(val == .Object);
    const obj = val.Object;
    try testing.expectEqualStrings("value", obj.get("key").?.String);
    try testing.expectEqual(123.45, obj.get("number").?.Number);
    try testing.expectEqual(true, obj.get("bool").?.Bool);
    try testing.expect(obj.get("null_val").? == .Null);

    const arr = obj.get("array").?.Array;
    try testing.expectEqual(3, arr.len);
    try testing.expectEqual(1.0, arr[0].Number);
    try testing.expectEqual(2.0, arr[1].Number);
    try testing.expectEqual(3.0, arr[2].Number);
}
