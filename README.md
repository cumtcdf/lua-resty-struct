# lua-resty-struct
A pure LuaJIT (no dependencies) struct library.

### Table of Contents
* [Motivation](#motivation)
* [Usage](#usage)
* [Installation](#installation)
* [Documentation](#documentation)
* [License](#license)
* [Other](#other)

### Motivation

This module is aimed at being a free of dependencies, performant and
complete struct library for LuaJIT and ngx_lua.

Use it like Python struct module.

[Back to TOC](#table-of-contents)

### Usage
```lua
local struct, err = require "resty.struct"
local bit = require "bit"
local strbyte = string.byte

local print = ngx and ngx.say or print

assert(struct, err)

local function tohex(stream)
    local result = ""
    for i = 1, #stream do
        result = result .. bit.tohex(strbyte(stream, i), 2)
    end
    return result
end

local s, err = struct:new("<fed2slqi")
assert(s, err)
local stream, size = s:pack(0.001,0.001,0.001,"234",1,2,3)
print(tohex(stream),size)
local f,e,d,s2,l,q,i = s:unpack(stream)
print(f,e,d,s2,l,q,i)
--0.0010000000474975      0.0010004043579102      0.001   23      1       2       3
```

[Back to TOC](#table-of-contents)

### Installation

This module can be installed through Luarocks:
```bash
$ luarocks install lua-resty-struct
```

[Back to TOC](#table-of-contents)

### Documentation
reference Python struct module

<https://docs.python.org/3.10/library/struct.html>

[Back to TOC](#table-of-contents)

### License

Work licensed under the MIT License.

[Back to TOC](#table-of-contents)

### Other

[`iryont/lua-struct`](https://github.com/openresty/lua-nginx-module#lua_code_cache)