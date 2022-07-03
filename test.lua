local struct, err = require "lib.resty.struct"
local strbyte = string.byte
local strchar = string.char


if not struct then
    print(err)
    return
end
local bin = require "bit"

local function tohex(stream)
    local result = ""
    for i = 1, #stream do
        result = result .. bit.tohex(strbyte(stream, i), 2)
    end
    return result
end

local function getline(key)
    local line = "-------------------------------------------------------"
    local len = #key
    local left = math.floor(len / 2)
    local right = len - left
    return line:sub(left, -2) .. key .. line:sub(right, -2), line .. line
end

local function test_string()
    local header, footer = getline("_string")
    print(header)
    local _string = struct:new('3s')
    assert(_string ~= nil)


    -- value is shorter than size
    local stream, size = _string:pack("12")
    assert(stream ~= nil and #stream == size)
    print("stream:", tohex(stream))
    assert(tohex(stream) == "313200")
    local value = _string:unpack(stream)
    print("value", value)
    assert(value == "12\0")

    -- value is longger than size
    stream, size = _string:pack("1234")
    assert(stream ~= nil and #stream == size)
    print("stream:", tohex(stream))
    assert(tohex(stream) == "313233")
    local value = _string:unpack(stream)
    print("value", value)
    assert(value == "123")

    print(footer)
end

local function test_number()

    local floats = {
        _float2_le = {
            struct = struct:new("<e"),
            values =
            {
                valid = -0.000098,
                invalid = -204800000.0001
            }
        },
        _float2_be = {
            struct = struct:new(">e"),
            values =
            {
                valid = -0.000098,
                invalid = -204800000.0001
            }
        },
        _float4_le = {
            struct = struct:new("<f"),
            values =
            {
                valid = -0.000098,
                invalid = 3.4028235E+38 * 2
            }
        },
        _float4_be = {
            struct = struct:new(">f"),
            values =
            {
                valid = -0.000098,
                invalid = 3.4028235E+38 * 2
            }
        },
        _float8_le = {
            struct = struct:new("<d"),
            values =
            {
                valid = -0.000098,
                invalid = -1.7976931348623157E+308 * 2
            }
        },
        _float8_be = {
            struct = struct:new(">d"),
            values =
            {
                valid = -0.000098,
                invalid = -1.7976931348623157E+308 * 2
            }
        },
        _byte = {
            struct = struct:new('B'),
            values =
            {
                valid = 0xff,
                invalid = -1
            }
        },
        _smallint_le = {
            struct = struct:new('<h'),
            values =
            {
                valid = 0xfff,
                invalid = -0xffff
            }
        },
        _smallint_be = {
            struct = struct:new('>h'),
            values =
            {
                valid = 0xfff,
                invalid = -0xffff
            }
        },
        _usmallint_le = {
            struct = struct:new('<H'),
            values =
            {
                valid = 0xffff,
                invalid = -1
            }
        },
        _usmallint_be = {
            struct = struct:new('>H'),
            values =
            {
                valid = 0xffff,
                invalid = -1
            }
        },
        _int_le = {
            struct = struct:new('<l'),
            values =
            {
                valid = 0xfffffff,
                invalid = -0xffffffff
            }
        },
        _int_be = {
            struct = struct:new('>l'),
            values =
            {
                valid = 0xfffffff,
                invalid = -0xffffffff
            }
        },
        _uint_le = {
            struct = struct:new('<L'),
            values =
            {
                valid = 0xfffffff,
                invalid = -1
            }
        },
        _uint_be = {
            struct = struct:new('>L'),
            values =
            {
                valid = 0xfffffff,
                invalid = -1
            }
        },
        _int8_le = {
            struct = struct:new('<q'),
            values =
            {
                valid = 0xffffffff + 0xfffffff + 1,
                invalid = -2 ^ (8 * 8)
            }
        },
        _int8_be = {
            struct = struct:new('>q'),
            values =
            {
                valid = 0xffffffff + 0xffffffff,
                invalid = -2 ^ (8 * 8)
            }
        },
        _uint8_le = {
            struct = struct:new('<Q'),
            values =
            {
                valid = 0xffffffff + 0xffffffff,
                invalid = -1
            }
        },
        _uint8_be = {
            struct = struct:new('>Q'),
            values =
            {
                valid = 0xffffffff + 0xffffffff,
                invalid = -1
            }
        }
    }
    for key, v in pairs(floats) do
        local lineheader, linefooter = getline(key)
        print(lineheader)
        local strc = v.struct
        assert(strc ~= nil)
        local valid = v.values.valid
        local invalid = v.values.invalid
        local stream, err = strc:pack(valid)
        assert(stream ~= nil)
        print("--valid--")
        print("stream:", tohex(stream))
        local value = strc:unpack(stream)
        print("value:", value)
        print("abs(valid - value)", math.abs(valid - value))
        stream, err = strc:pack(invalid)
        assert(stream == nil)
        print("--invalid--")
        print("err:", err)
        print(linefooter)
    end
end

test_string()
test_number()
