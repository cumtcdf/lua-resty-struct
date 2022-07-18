local tblinsert    = table.insert
local setmetatable = setmetatable
local tonumber     = tonumber

local strsub   = string.sub
local strfmt   = string.format
local strbyte  = string.byte
local strchar  = string.char
local strlower = string.lower
local strlen   = string.len
local strfind  = string.find

local floor = math.floor
local frexp = math.frexp
local ldexp = math.ldexp
local abs   = math.abs
local inf   = 1 / 0 --math.huge
local nan   = 0 / 0

local bit    = require "bit"
local band   = bit.band
local bxor   = bit.bxor
local bor    = bit.bor
local lshift = bit.lshift
local rshift = bit.rshift
local tohex  = bit.tohex
local bnot   = bit.bnot

local UNSIGNED, SIGNED = "UNSIGNED", "SIGNED"
local BE, LE = "BE", "LE"

local _M = {}

local byteorder = {
    ["@"] = LE,
    ["="] = LE,
    ["<"] = LE,
    [">"] = BE,
    ["!"] = BE,
}

---comment
---@param value integer
---@param n? integer
---@param borl? string
---@return string
local function integer2stream(value, n, borl)
    borl = borl or LE
    n = n or 1
    local d = value
    local result = ""
    for i = 1, n do
        result = borl == BE and (strchar(band(d, 0xFF)) .. result) or (result .. strchar(band(d, 0xFF)))
        if i < n then
            d = floor(d / 0x100)
        end
    end
    return result
end

---comment
---@param stream string
---@param u? string
---@param borl? string
local function stream2integer(stream, u, borl)
    u = u or SIGNED
    borl = borl or LE

    local f = 1
    if u == SIGNED then
        local b1 = borl == BE and strbyte(stream, 1) or strbyte(stream, -1)
        if band(rshift(b1, 7), 7) == 1 then
            f = -1
        end
    end
    local result = 0
    for i = 1, strlen(stream) do
        local index = borl == BE and i or -i
        local b = strbyte(stream, index)
        if f == -1 then
            b = band(bnot(b), 0xff)
        end
        result = result * 0x100 + b
    end
    return f == -1 and -result - 1 or result
end

---comment
---@param opt string
---@return string
local function get_signed(opt)
    if opt == strlower(opt) then
        return SIGNED
    end
    return UNSIGNED
end

---comment
---@param len integer
---@return function
local function get_stream_validator(len)
    ---comment
    ---@param self any
    ---@param stream string
    ---@return string|nil
    ---@return nil|string
    return function(self, stream)
        if strlen(stream) >= len then
            return strsub(stream, 1, len), strsub(stream, len + 1, -1)
        end
        return nil, strfmt("stream has not enough chars expect %d, actual %d", len, strlen(stream))
    end
end

---comment
---@param opt string
---@param len integer
---@param u string
---@return function
local function get_integer_validator(opt, len, u)
    local sign = u == SIGNED
    local max = sign and 2 ^ (len * 8 - 1) - 1 or 2 ^ (len * 8) - 1
    local min = sign and -1 * 2 ^ (len * 8 - 1) or 0
    ---comment
    ---@param self any
    ---@param value integer
    ---@return integer|nil
    ---@return nil|string
    return function(self, value)
        local v = tonumber(value)
        if not v then
            return nil, strfmt("value [%s] is not valid number", value)
        end
        v = floor(v)
        if v > max or v < min then
            return nil, strfmt("value [%s] is out of range, opt %s maxvalue is %s minvalue is %s", v, opt, max, min)
        end
        return v, nil
    end
end

---comment
---@param self table
---@param value number
---@return integer|nil
---@return number|string
---@return integer|nil
local function float2_value_validator(self, value)
    local sign, e, bits = 0, 0, 0
    if value == 0.0 then
        sign, e, bits = 0, 0, 0
    elseif value == nan then
        sign, e, bits = 0, 0x1f, 0x200
    elseif value == -nan then
        sign, e, bits = 1, 0x1f, 0x200
    elseif value == inf or value == -inf then
        sign, e, bits = value < 0 and 1 or 0, 0x1f, 0
    else
        sign = value < 0 and 1 or 0
        if sign == 1 then
            value = -value
        end
        local f
        f, e = frexp(value)
        if f < 0.5 and f >= 1 then
            return nil, "frexp() result out of range"
        end
        f = f * 2
        e = e - 1
        if e >= 16 then
            goto Overflow
        elseif e < -25 then
            --/* |x| < 2**-25. Underflow to zero. */
            f = 0.0
            e = 0
        elseif e < -14 then
            --/* |x| < 2**-14. Gradual underflow */
            f = ldexp(f, 14 + e)
            e = 0
        else --/* if (!(e == 0 && f == 0.0)) */
            e = e + 15
            f = f - 1.0 --/* Get rid of leading 1 */
        end
        f = f * 1024.0
        bits = floor(f)
        assert(bits < 1024)
        assert(e < 31)
        if (f - bits > 0.5) or ((f - bits == 0.5) and bits % 2 == 1) then
            bits = bits + 1
            if bits == 1024 then
                bits = 0
                e = e + 1
                if e == 31 then
                    goto Overflow
                end
            end
        end
    end
    do
        return sign, e, bits
    end
    ::Overflow::
    return nil, "float too large to pack with e format"
end

---comment
---@param self any
---@param value number
---@return integer|nil
---@return integer|string
---@return number|nil
---@return integer|nil
local function float4_value_validator(self, value)

    local sign, e, f, fbits = 0, 0, 0.0, 0
    if value == 0.0 then
        sign, e, fbits = 0, 0, 0
    elseif value == nan then
        sign, e, fbits = 0, 0xff, 0x200
    elseif value == -nan then
        sign, e, fbits = 1, 0xff, 0x200
    elseif value == inf or value == -inf then
        sign, e, fbits = value < 0 and 1 or 0, 0xff, 0
    else
        if value < 0 then
            sign = 1
            value = -value
        end
        f, e = frexp(value)
        if f >= 0.5 and f < 1 then
            f = f * 2
            e = e - 1
        elseif f == 0.0 then
            e = 0
        else
            return nil, "frexp() result out of range"
        end
        if e >= 128 then
            goto Overflow
        elseif e < -126 then
            f = ldexp(f, 126 + e)
            e = 0
        elseif not (e == 0 and f == 0.0) then
            e = e + 127
            f = f - 1.0 --/* Get rid of leading 1 */
        end
        f = f * 8388608.0 -- /* 2**23 */
        fbits = floor(f + 0.5)
        assert(fbits <= 8388608)
        if rshift(fbits, 23) > 0 then
            fbits = 0
            e = e + 1
            if e > 255 then
                goto Overflow
            end
        end
    end
    do return sign, e, fbits end
    ::Overflow::
    return nil, "float too large to pack with f format"
end

---comment
---@param self any
---@param value number
---@return integer|nil
---@return integer|string
---@return number|nil
---@return integer|nil
---@return integer|nil
local function float8_value_validator(self, value)
    local sign, e, f, fhi, flo = 0, 0, 0.0, 0, 0
    if value < 0 then
        sign = 1
        value = -value
    end
    f, e = frexp(value)
    if f >= 0.5 and f < 1 then
        f = f * 2
        e = e - 1
    elseif f == 0.0 then
        e = 0
    else
        return nil, "frexp() result out of range"
    end
    if e >= 1024 then
        goto Overflow
    elseif e < -1022 then
        f = ldexp(f, 1022 + e)
        e = 0
    elseif not (e == 0 and f == 0.0) then
        e = e + 1023
        f = f - 1.0 --/* Get rid of leading 1 */
    end
    f = f * 268435456.0 -- /* 2**28 */
    fhi = floor(f)
    assert(fhi < 268435456)
    f = f - fhi
    f = f * 16777216.0 --/* 2**24 */
    flo = floor(f + 0.5)
    assert(flo <= 16777216)
    if rshift(flo, 24) > 0 then
        flo = 0
        fhi = fhi + 1
        if rshift(fhi, 28) > 0 then
            fhi = 0
            e = e + 1
            if e > 2047 then
                goto Overflow
            end
        end
    end
    do return sign, e, f, fhi, flo end
    ::Overflow::
    return nil, "float too large to pack with d format"
end

---comment
---@param stream string
---@param borl string
---@return number
local function float2_unpack(stream, borl)
    local sign, e, f, x = 0, 0, 0.0, 0.0
    local b1, b2 = strbyte(stream, 1, 2)

    if borl == LE then
        b1, b2 = b2, b1
    end
    sign = band(rshift(b1, 7), 1)
    e = rshift(band(b1, 0x7c), 2)
    f = lshift(band(b1, 0x03), 8)
    f = bor(f, b2)

    if e == 0x1f then
        if f == 0 then
            return sign == 1 and -inf or inf
        else
            return sign == 1 and -nan or nan
        end
    end
    x = f / 1024.0
    if e == 0 then
        e = -14
    else
        x = x + 1.0
        e = e - 15
    end
    x = ldexp(x, e)
    if sign == 1 then
        x = -x
    end
    return x
end

---comment
---@param stream string
---@param borl string
---@return number|nil
---@return nil|string
local function float4_unpack(stream, borl)
    local sign, e, f, x = 0, 0, 0.0, 0.0
    local b1, b2, b3, b4 = strbyte(stream, 1, 4)
    if borl == LE then
        b1, b2, b3, b4 = b4, b3, b2, b1
    end
    --/* First byte */
    sign = band(rshift(b1, 7), 1)
    e = lshift(band(b1, 0x7f), 1)
    -- /* Second byte */
    e = bor(e, band(rshift(b2, 7), 1))
    f = lshift(band(b2, 0x7f), 16)
    if e == 255 then
        return nil, "can't unpack IEEE 754 special value on non-IEEE platform"
    end
    --/* Third byte */
    f = bor(lshift(b3, 8), f)
    --/* Fourth byte */
    f = bor(b4, f)


    x = f / 8388608.0
    -- /* XXX This sadly ignores Inf/NaN issues */
    if e == 0 then
        e = -126;
    else
        x = x + 1.0;
        e = e - 127;
    end
    x = ldexp(x, e);

    if sign == 1 then
        x = -x
    end

    return x
end

---comment
---@param stream string
---@param borl string
---@return number|nil
---@return nil|string
local function float8_unpack(stream, borl)
    local sign, e, fhi, flo, x = 0, 0, 0, 0, 0.0
    local b1, b2, b3, b4, b5, b6, b7, b8 = strbyte(stream, 1, 8)
    if borl == LE then
        b1, b2, b3, b4, b5, b6, b7, b8 = b8, b7, b6, b5, b4, b3, b2, b1
    end
    --/* First byte */
    sign = band(rshift(b1, 7), 1)
    e = lshift(band(b1, 0x7F), 4)

    --/* Second byte */
    e = bor(e, band(0xf, rshift(b2, 4)))
    fhi = lshift(band(0xf, b2), 24)

    if e == 2047 then
        return nil, "can't unpack IEEE 754 special value on non-IEEE platform"
    end
    --/* Third byte */
    fhi = bor(fhi, lshift(b3, 16))
    --/* Fourth byte */
    fhi = bor(fhi, lshift(b4, 8))
    --/* Fifth byte */
    fhi = bor(fhi, b5)
    -- /* Sixth byte */
    flo = lshift(b6, 16)
    --/* Seventh byte */
    flo = bor(flo, lshift(b7, 8))
    --/* Eighth byte */
    flo = bor(flo, b8)


    x = fhi + flo / 16777216.0 --/* 2**24 */
    x = x / 268435456.0 --/* 2**28 */

    if e == 0 then
        e = -1022
    else
        x = x + 1.0
        e = e - 1023
    end

    x = ldexp(x, e)
    if sign > 0 then
        x = -x
    end
    return x
end

---comment
---@param len integer
---@return function
local function get_string_validater(len)
    ---comment
    ---@param self any
    ---@param value string
    ---@return string|nil
    ---@return nil|string
    return function(self, value)
        if type(value) == "string" and strlen(value) == len then
            return value
        end
        return nil, strfmt("value [%s] is too long, expect %d, actual %d", value, len, strlen(value))
    end
end

---comment
---@return function
local function get_boolean_validater()
    return function(self, value)
        return value and true or false, nil
    end
end

local convertors = {
    -- ["x"] = 0,
    ["c"] = {
        value_validator = get_string_validater(1),
        stream_validator = get_stream_validator(1),
        reader = function(self, stream)
            local res, err = self:stream_validator(stream)
            return res, err
        end,
        writer = function(self, stream, value)
            local res, err = self:value_validator(value)
            if res then
                return stream .. strchar(band(strbyte(res, 1), 0xff)), 1
            end
            return res, err
        end
    },
    ["?"] = {
        value_validator = get_boolean_validater(),
        stream_validator = get_stream_validator(1),
        reader = function(self, stream)
            local res, err = self:stream_validator(stream)
            if res then
                return stream2integer(res, UNSIGNED, self.borl) > 0, err
            end
            return res, err
        end,
        writer = function(self, stream, value)
            local res, err = self:value_validator(value)
            return stream .. integer2stream(res and 1 or 0, 1, self.borl), 1
        end
    }
}

---comment
---@param opt string
---@return nil|integer
local function get_opt_size(opt)
    if strfind(opt, "[bBsc]") then
        return 1
    elseif strfind(opt, "[hHe]") then
        return 2
    elseif strfind(opt, "[iIlLf]") then
        return 4
    elseif strfind(opt, "[qQd]") then
        return 8
    end
    return nil
end

---comment
---@param opt string
---@param borl string
---@return table|nil
---@return nil|string
local function get_convertor(opt, borl)
    local size = get_opt_size(opt)
    if not size then
        return nil, strfmt("invalid struct format char [%s]", opt)
    end
    local res = convertors[opt]
    if res then
        res.size = size
        res.borl = borl
        res.opt = opt
        return res
    end
    res = {
        size = size,
        borl = borl,
        opt = opt
    }

    if strfind(opt, "[bBhHiIlLQq]") then
        res.value_validator = get_integer_validator(opt, size, get_signed(opt))
        res.stream_validator = get_stream_validator(size)
        res.reader = function(self, stream)
            local s, err = self:stream_validator(stream)
            if s then
                return stream2integer(s, get_signed(opt), self.borl), err
            end
            return s, err
        end
        res.writer = function(self, stream, value)
            local s, err = self:value_validator(value)
            if s then
                return stream .. integer2stream(s, size, self.borl), size
            end
            return s, err
        end
    elseif strfind(opt, "[efd]") then
        if opt == "e" then
            res.value_validator = float2_value_validator
            res.stream_validator = get_stream_validator(2)
            res.writer = function(self, stream, value)
                local sign, e, bits = self:value_validator(value)
                if not sign then
                    return nil, e
                end
                bits = bor(bits, bor(lshift(e, 10), lshift(sign, 15)))
                local b1, b2 = band(rshift(bits, 8), 0xff), band(bits, 0xFF)
                if self.borl == LE then
                    return stream .. strchar(b2, b1), 2
                end
                return stream .. strchar(b1, b2), 2
            end
            res.reader = function(self, stream)
                local s, err = self:stream_validator(stream)
                if s then
                    return float2_unpack(s, self.borl), err
                end
                return s, err
            end
        elseif opt == 'f' then
            res.value_validator = float4_value_validator
            res.stream_validator = get_stream_validator(4)
            res.writer = function(self, stream, value)
                local sign, e, fbits = self:value_validator(value)
                if not sign then
                    return nil, e
                end
                local b1 = bor(lshift(sign, 7), rshift(e, 1))
                local b2 = bor(lshift(band(e, 1), 7), rshift(fbits, 16))
                local b3 = band(rshift(fbits, 8), 0xff)
                local b4 = band(fbits, 0xff)
                if self.borl == LE then
                    return stream .. strchar(b4, b3, b2, b1), 4
                end
                return stream .. strchar(b1, b2, b3, b4), 4
            end
            res.reader = function(self, stream)
                local s, err = self:stream_validator(stream)
                if s then
                    return float4_unpack(s, self.borl), err
                end
                return s, err
            end
        elseif opt == "d" then
            res.value_validator = float8_value_validator
            res.stream_validator = get_stream_validator(8)
            res.writer = function(self, stream, value)
                local sign, e, f, fhi, flo = self:value_validator(value)
                if not sign then
                    return nil, e
                end
                local b1 = bor(lshift(sign, 7), rshift(e, 4))
                local b2 = bor(lshift(band(e, 0xF), 4), rshift(fhi, 24))
                local b3 = band(rshift(fhi, 16), 0xff)
                local b4 = band(rshift(fhi, 8), 0xff)
                local b5 = band(fhi, 0xff)
                local b6 = band(rshift(flo, 16), 0xff)
                local b7 = band(rshift(flo, 8), 0xff)
                local b8 = band(flo, 0xff)
                if self.borl == LE then
                    return stream .. strchar(b8, b7, b6, b5, b4, b3, b2, b1), 8
                end
                return stream .. strchar(b1, b2, b3, b4, b5, b6, b7, b8), 8
            end
            res.reader = function(self, stream)
                local s, err = self:stream_validator(stream)
                if s then
                    return float8_unpack(s, self.borl), err
                end
                return s, err
            end

        end
    elseif strfind(opt, "s") then
        res.value_validator = function(self, value)
            value = tostring(value)
            if strlen(value) < self.size then
                local lstr = strlen(value)
                local size = self.size
                for i = 1, size - lstr do
                    value = value .. '\0'
                end
            end
            return strsub(value, 1, self.size)
        end
        res.stream_validator = function(self, value)
            return get_stream_validator(self.size)(self, value)
        end
        res.writer = function(self, stream, value)
            local s = self:value_validator(value)
            return stream .. s, self.size
        end
        res.reader = function(self, stream)
            return self:stream_validator(stream)
        end
    end
    return res
end

---comment
---@param fmt string
---@return table|nil
---@return integer|string
local parse_format = function(fmt)
    local strcount = ""
    local size = 0
    local borl = LE

    local opt = strsub(fmt, 1, 1)
    if byteorder[opt] then
        borl = byteorder[opt]
        fmt = strsub(fmt, 2, -1)
    end
    local result = {
        borl = borl
    }
    local index = 0
    for i = 1, #fmt do
        local c = strsub(fmt, i, i)
        if strbyte(c, 1) >= strbyte('0', 1) and strbyte(c, 1) <= strbyte('9', 1) then
            strcount = strcount .. c
        else
            local convertor = get_convertor(c, borl)
            if not convertor then
                return nil, strfmt("invalid struct format char [%s]", c)
            end
            local itemsize = convertor.size
            if c == "s" then
                index = index + 1
                itemsize = tonumber(strcount) or 1
                convertor.size = itemsize
                result[index] = convertor
                size = size + itemsize
            else
                local count = tonumber(strcount) or 1
                for j = 1, count do
                    index = index + 1
                    result[index] = convertor
                    size = size + itemsize
                end
            end
            strcount = ""
        end
    end
    return result, size
end

---comment
---@param self table
---@param fmt string
---@return table|nil
---@return nil|string|integer
_M.new = function(self, fmt)
    local result = {
        format = fmt
    }
    local res, size = parse_format(fmt)
    if not res then
        return nil, size
    end
    result.size = size
    result.convertors = res
    return setmetatable(result, { __index = _M })
end

---comment
---@param self table
---@param ... any
---@return string|nil
---@return integer|string
_M.pack = function(self, ...)
    local vars = { ... }
    local var_count = #vars
    local con_cont = #self.convertors
    if var_count ~= con_cont then
        return nil, strfmt("pack expected %d items for packing (got %d)", con_cont, var_count)
    end
    local stream, err = "", nil
    local len = 0
    for index, value in ipairs(vars) do
        local convertor = self.convertors[index]
        stream, err = convertor:writer(stream, value)
        if not stream then
            return nil, err
        end
        len = len + err
    end
    return stream, len
end

---comment
---@param self table
---@param stream string
---@return nil
---@return string
_M.unpack = function(self, stream)
    local stream_len = strlen(stream)
    local size = self.size
    if stream_len ~= size then
        return nil, strfmt("unpack requires a buffer of %d bytes (got %d)", size, stream_len)
    end
    local result = {}
    for index, convertor in ipairs(self.convertors) do
        local value
        value, stream = convertor:reader(stream)
        if not value then
            return nil, stream
        end
        tblinsert(result, value)
    end
    return unpack(result)
end

_M.unpack_from = function(self, stream, offset)
    local from = offset + 1
    local to = from + self.size - 1
    local to_unpack = strsub(stream, from, to)
    return self:unpack(to_unpack)
end

return _M
