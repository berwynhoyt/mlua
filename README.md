# MLua - Lua for the MUMPS database

## Overview

MLua is a Lua language plugin for the MUMPS database. It provides the means to call Lua from within M. Here is [more complete documentation](https://dev.anet.be/doc/brocade/mlua/html/index.html) of where this project is headed. MLua incorporates [lua-yottadb](https://github.com/orbitalquark/lua-yottadb/) (cf. YDB's [Multi-Language Programmer's Guide](https://docs.yottadb.com/MultiLangProgGuide/luaprogram.html)) which operates in the other direction, letting Lua code access an M database.

Invoking a Lua command from M is easy:

```lua
$ ydb
YDB>do &mlua.lua("print('Hello World!')")
Hello world!
```

(Note: prior to YDB v1.35 you'll want to prefix your command with `u $p ` to flush YDB's '\n' to stdout before calling Lua)

Now let's access a YDB local. At the first print statement we'll intentionally create a Lua syntax error:

```lua
YDB>do &mlua.lua("ydb = require 'yottadb'")
YDB>set hello="Hello World!"

YDB>do &mlua.lua("return ydb.get('hello')")
Hello World!
YDB>do &mlua.lua("return ydb.get('hello')",.output)  ; capture return value in `output`

YDB>w output
Hello World!
YDB>
```

Since all Lua code chunks are actually functions, you can also pass parameters and return values:

```lua
YDB>do &mlua.lua("print('params:',...) return 'Done'",.out,,1,2)  w out
params:	1	2
Done
YDB>
```

For the sake of speed, it is also possible to pre-compile a function. If the string starts with '>', the rest of the string is taken as the name of a global function to invoke, rather than a string to compile:

```lua
YDB>do &mlua.lua("function add(a,b) return a+b end")
YDB>do &mlua.lua(">add",.out,,3,4) w out
7
```

### Example Lua task

Let's use Lua to calculate the height of your neighbour's oak trees based on the length of their shadow and the angle of the sun. First we enter the raw data into YDB, then run `tree_height.lua` to fetch from YDB and calculate:

```lua
YDB>set ^oaks(1,"shadow")=10,^("angle")=30
YDB>set ^oaks(2,"shadow")=13,^("angle")=30
YDB>set ^oaks(3,"shadow")=15,^("angle")=45

YDB>zwrite ^oaks  ;same as Lua command: ydb.dump('^oaks')
^oaks("1","angle")="30"
^oaks("1","shadow")="10"
^oaks("2","angle")="30"
^oaks("2","shadow")="13"
^oaks("3","angle")="45"
^oaks("3","shadow")="15"

YDB>do &mlua.lua("dofile 'tree_height.lua'")  ;see file contents below
YDB>do &mlua.lua("calc_height( ydb.node('^oaks') )")
Oak 1 is 5.8m high
Oak 2 is 7.5m high
Oak 3 is 15.0m high

YDB>zwr ^oaks(,"height")
^oaks(1,"height")=5.7735026918963
^oaks(2,"height")=7.5055534994651
^oaks(3,"height")="15.0"
```

The function `calc_height()` fetches data from YDB and calculates oak heights. It is defined in `tree_height.lua` as follows:

```lua
function calc_height(oaks)
    for oaktree, _value, index in pairs(oaks) do
        height = oaktree.shadow.__ * math.tan( math.rad(oaktree.angle.__) )
        print(string.format('Oak %s is %.1fm high', index, height))
        oaktree.height.__ = height  -- save back into YDB
    end
end
```

Further documentation of Lua's API for YDB is documented in YDB's [Multi-Language Programmer's Guide](https://docs.yottadb.com/MultiLangProgGuide/luaprogram.html), including locks and transactions.

### MLUA_INIT

You will find that you need to do `ydb = require 'yottadb'` every time your start YDB, so that Lua can access yottadb functions. There is a way to automate this whenever MLua first starts. Simply set your MLUA_INIT environment variable with`export MLUA_INIT="ydb=require'yottadb'"`

Alternatively, if you want to run a whole file of Lua commands when MLua first starts, simply point it to a file using the `@` symbol: (e.g. with `export MLUA_INIT=@startup.lua`) and `startup.lua` will run whenever &mlua creates a new lua_State. It works just like Lua's standard LUA_INIT, except operates when MLua starts instead of when Lua starts.

### MLua wrapper function

You may have noticed that invoking MLua to check for errors and capture output is slightly awkward and looks something like `set error=$$mlua.lua("return 1",.output) if output=1 ...` or worse. Don't you wish you could simply do `if $$lua("return 1") ...`?

Well, you can actually do that if you add the following M wrapper function into your M routine. It will automatically raise errors and return the output/error. Note that it handles up to 8 optional arguments, which matches the default limit specified in mlua.xc:

```lua
lua(lua,a1,a2,a3,a4,a5,a6,a7,a8)
 new o,result
 set result=$select($data(a1)=0:$&mlua.lua(lua,.o),$data(a2)=0:$&mlua.lua(lua,.o,,a1),$data(a3)=0:$&mlua.lua(lua,.o,,a1,a2),$data(a4)=0:$&mlua.lua(lua,.o,,a1,a2,a3),$data(a5)=0:$&mlua.lua(lua,.o,,a1,a2,a3,a4),$data(a6)=0:$&mlua.lua(lua,.o,,a1,a2,a3,a4,a5),$data(a7)=0:$&mlua.lua(lua,.o,,a1,a2,a3,a4,a5,a6),$data(a8)=0:$&mlua.lua(lua,.o,,a1,a2,a3,a4,a5,a6,a7),0=0:$&mlua.lua(lua,.o,,a1,a2,a3,a4,a5,a6,a7,a8))
 if result write o set $ecode=",U1,MLua,"
 quit:$quit o quit
```

There's obviously is a mild performance penalty, so don't use this if speed is paramount.

## API

Here is the list of supplied functions, [optional parameters in square brackets]:

- **mlua.lua**(code\[,.output]\[,luaState]\[,param1]\[,...])
- **mlua.open**(\[.output]\[,flags])
- **mlua.close**(luaState)
- **mlua.version**()

**`mlua.lua()`** accepts a string of Lua code which it compiles and runs as a Lua 'chunk'. Note that Lua chunks are actually functions, so values may be returned and optional function parameters passed (param1, ...). For the sake of speed, it also possible to run a pre-compiled function by name. If the string starts with '>', the rest of the string is taken as the name of a global function to invoke, rather than a string to compile, as in `'>math.abs'`.

Be aware that all parameters are strings and are not automatically converted to Lua numbers. Parameters are currently limited to 8, but this may easily be increased in mlua.xc.

On success, `mlua.lua()` sends the returned string to stdout or fills .output (if >1 parameters are supplied). If the return value is not a string, it is converted to a string as follows:

* nil ==> "" (empty string)
* boolean ==> "0" or "1"
* number ==> decimal string representation. Numbers >= 1e14 are coded as "1E+14": use M's unary + in front of them to force numeric interpretation
* string ==> a string which may contain NUL characters. It is truncated at 1048576 characters, the maximum YDB string length. This makes YDB allocate the whole 1MB for return data, but it's worth it since returning strings this way is faster than using `ydb.set()`.
* other types ==> "(typename)"

If the luaState handle is missing or 0, mlua.lua() will run the code in the default global lua_State, automatically opening it the first time you call mlua.lua(). Alternatively, you can supply a luaState with a handle returned by mlua.open() (see below) to run code in a different lua_State.

On error, `mlua.lua()` returns nonzero and the error message is sent to stdout or returned in .output (if >1 parameter supplied). Note that the error value return is currently equal to -1. This may be enhanced in the future to also return positive integers equal to ERRNO or YDB errors whenever YDB functions called by Lua are the cause of the error. However, for now, all errors return -1 and any YDB error code is encoded into the error message just like any other Lua error (Lua 5.4 does not yet support coded or named errors).

**`mlua.open()`** creates a new 'lua_State' which contains a new Lua context, stack, and global variables, and can run independently and in parallel with other lua_States (see the Lua Reference Manual on the [Application Programmer Interface](https://www.lua.org/manual/5.4/manual.html#4)). You may add optional flags defined in mlua.h: MLUA_IGNORE_INIT (=0x01) to suppress running of MLUA_INIT when the lua_State is opened, and MLUA_ALLOW_SIGNALS (see below).

On success, `mlua.open()` returns a luaState handle which can be passed to mlua.lua(). On error, it returns zero and the error message is sent to stdout or returned in .output if supplied.

**`mlua.close()`** can be called if you have finished using the lua_State, in order to free up any memory that a lua_State has allocated, first calling any garbage-collection meta-methods you have introduced in Lua.
`mlua.close(0)` will close the default Lua state, and 
`mlua.close()` will close all Lua states.
It returns 0 on success, -1 if the supplied handle is invalid, and -2 if the supplied handle is already closed.

**`mlua.version()`** returns the current MLua version number as decimal XXYYZZ where XX=major, YY=minor, ZZ=release

## Versions & Acknowledgements

MLua requires YDB 1.34 or higher and Lua 5.1 or higher.

MLua's primary author is Berwyn Hoyt. MLua incorporates [lua-yottadb](https://github.com/orbitalquark/lua-yottadb/) by [Mitchell](https://github.com/orbitalquark), which is based heavily on [YDBPython](https://gitlab.com/YottaDB/Lang/YDBPython). Both were sponsored by, and are copyright © 2022, [University of Antwerp Library](https://www.uantwerpen.be/en/library/). They are provided under the same license as YottaDB: the [GNU Affero General Public License version 3](https://www.gnu.org/licenses/agpl-3.0.txt).

MLua also uses [Lua](https://www.lua.org/) (copyright © 1994–2021 Lua.org, PUC-Rio) and [YottaDB](https://yottadb.com/) (copyright © 2017-2019, YottaDB LLC). Both are available under open source licenses.

## Installation

Prerequisites: linux, gcc, yottadb
Install YottaDB per the [Quick Start](https://docs.yottadb.com/MultiLangProgGuide/MultiLangProgGuide.html#quick-start) guide instructions or from [source](https://gitlab.com/YottaDB/DB/YDB).

To install MLua itself:

```shell
git clone `<mlua repository>`  # fetch this code repository
cd mlua
make                    # download and then build the Lua language, then build MLua
sudo make install       # install to the system
```

### Explanation

The final line above copies mlua.xc and mlua.so, typically into $ydb_dist/plugin, and _yottadb.so and yottadb.lua into the system's Lua directories.

If you need to build against a version of Lua other than the default, e.g. Lua 5.1.5:

```sh
make LUA_BUILD=5.1.5 && sudo make LUA_BUILD=5.1.5 install
```

If you need to install into a non-standard YDB directory, or library directory other than `/usr/local` (say `~/.local`), change the last line to something like:

```shell
make install YDB_INSTALL=<your_ydb_plugin_directory> PREFIX=~/.local
```

MLua is implemented as a shared library mlua.so which also embeds Lua and the Lua library. There is no need to install Lua separately.

Instead of installing to the system, you can also install files into a local directory `deploy` with `make install local`.

Check that everything is in the right place:

```shell
$ ls -1 `pkg-config --variable=prefix yottadb`/plugin/mlua.*
/usr/local/lib/yottadb/r134/plugin/mlua.so
/usr/local/lib/yottadb/r134/plugin/mlua.xc
$ ls -1 /usr/local/share/lua/*/yottadb.* /usr/local/lib/lua/*/_yottadb.*
/usr/local/lib/lua/5.4/_yottadb.so
/usr/local/share/lua/5.4/yottadb.lua
```

The ydb_env_set script provided by YDB, automatically provides the environment variables needed for YDB to access any plugin installed in the plugin directory shown here. For old releases of the database you may need to provide ydb_xc_mlua environment variable explicitly.

### Shared vs Embedded

By default, `make` embeds the entire Lua into `mlua.so` so that it is entirely self-contained. However, some may prefer to build Lua as a shared library (for example, if you want to share the library you built Apache's `mod_lua` with). In that case, you can build `libluaX.Y.so` with this:

```shell
make SHARED_LUA=yes
```

After the above, `sudo make install` will also copy `libluaX.Y.so` to `/usr/local/lib` (you can alter that path by appending `LIB_INSTALL=<path>`).

Alternatively, if you already have a `libluaX.Y.so` on your system, you can specify the path to that shared library like this:

```shell
make SHARED_LUA=/usr/local/lib/liblua5.4.so
```

### Updating MLua

To update both MLua and lua-yottadb from the internet and build+install:

```shell
make update
make install
```

### MLua as default Lua

If you also want to install the Lua built by MLua into your system. But be aware that it is built as Position Independent Code (PIC), so it may be ever so slightly slower than any system Lua, typically at `/usr/bin/lua`. To install to your system:

```shell
sudo make install-lua
```

You may also need to double-check that /usr/local/bin is in your path and/or run `hash lua` to refresh bash's cached PATH so it can find the new /usr/local/bin/lua.

## Testing

To test MLua, simply type one of the following:

```shell
make test       # basic MLua unit tests
make testall    # test MLua against every supported version of Lua
make benchmark  # perform a set of speed tests
```

Some benchmarks are automatically installed by the Makefile. Others will require manual installation of certain Lua modules: for example `luarocks install hmac` to get a SHA library for lua. But running `make benchmarks` will note these requirements for you. There is further comment on these benchmarks in the [benchmarks/README.md](benchmarks/README.md).

## Release

To release a new version of MLua:

- Test it first with `make testall`
- Update the version number in `mlua.h` and the version history that precedes it.
- To create a version tag in git and create a LuaRock, run:

```shell
make release
```

## Technical details

### Thread Safety

Lua co-routines, are perfectly safe to use with YDB, since they are cooperative rather than preemptive. However, MLua does not currently support multi-threaded applications – which would require [these lua-yottadb changes](https://github.com/anet-be/lua-yottadb#thread-safety).

### Signals & EINTR errors

Your MLua code must treat signals with respect. If your Lua code doesn't use slow or blocking IO like user input or pipes then you should have nothing to worry about. But if you're getting `Interrupted system call` (EINTR) errors from Lua, then you need to read this section.

YDB uses signals heavily (especially SIGALRM: see below). This means that YDB signal/timer handlers may be called while running Lua code. Normally this doesn't matter, but if your Lua code is doing blocking IO operations (using read/write/open/close), then these operations may return the EINTR error. Lua C code itself is not written to retry this error condition, so your software will fail unnecessarily unless you handle them. If you really *do* wish to handle EINTR errors yourself, you should also call YDB API function [ydb_eintr_handler()](https://docs.yottadb.com/MultiLangProgGuide/cprogram.html#ydb-eintr-handler-ydb-eintr-handler-t) whenever you get an EINTR error.

MLua offers a mechanism to resolve this automatically by blocking YDB signals until your Lua function is finished. To use it, simply open your lua_State using `mlua_open()` with the `MLUA_BLOCK_SIGNALS` flag (0x04). Be aware that if you use signal blocking with long-running Lua code, the database will not run timers until your Lua code returns (though it can flush database buffers: see the note on SIGALRM below). Be aware that setting up signal blocking is slow, so using `MLUA_BLOCK_SIGNALS` will more than double the mlua.lua() calling overhead (adding about 1.4 microseconds, compared to 0.9 microseconds when running a pre-compiled function like `>math.abs` without blocking – see `make benchmarks`).

For further details, refer to [lua-yottadb notes on specific signals](https://github.com/anet-be/lua-yottadb#specific-signals), which also apply to MLua.

### Quirks

Be aware that since different versions of Lua act differently, MLua will also act differently. This produces quirks like the following:

1. Number parameters are passed as strings, and returned as strings using Lua's number conversion, e.g.:

   ```lua
   YDB>do &mlua.lua("function add(a,b) return a+b end")
   YDB>do &mlua.lua(">add",.out,,3,4) w out
   7
   ```

   This outputs "7" for all Lua versions except Lua 5.3, which returns "7.0". This is because all numbers are passed as strings, and Lua < 5.4 converts strings to floats but Lua < 5.3 prints floats without the `.0` if possible, whereas Lua 5.3 prints floats with the `.0` And Lua >5.3 (e.g. 5.4) recognises strings '3' and '4' as integers, not floats: so its sum produces an integer as string "7".

## Troubleshooting

### Trouble building MLua

1. Why can't it find <libyottadb.h>?

   Make sure you have the prerequisites installed, including the yottadb package.

### Trouble running MLua

1. Why do I get error: `ydb_xc_mlua/GTMXC_mlua not set`?

   This is an environment variable that is supposed to be set by `ydb_env_set` which is a script that is normally run when you type `ydb`. On my machine, `ydb` runs a bash script at /usr/local/lib/yottadb/r134/ydb which, in turn, sources `ydb_env_set`. That script is responsible to set the ydb_xc_mlua environment variables required for every YDB plugin in the YDB plugin directory. On my machine, for example, it sets: `ydb_xc_mlua=/usr/local/lib/yottadb/r134/plugin/mlua.xc`

   The fact that this is not being set for you may mean you're not running `ydb` the normal way. Perhaps you are running `yottadb` instead, without the `ydb` wrapper script. In that case you will need to create the `ydb_xc_mlua` environment variable yourself, to point to your mlua.xc file.

3. When I `require 'yottadb'` why do I get `error loading module '_yottadb' from file '**/_yottadb.so':`?

   TLDR: Try to re-run MLua's `make install`
   
   This will fix the problem if your `mlua.so` and `_yottadb.so` were built against different Lua versions. This sometimes happens if you build and install lua-yottadb separately from MLua. You can test which Lua version mlua.so expects, and compare the search path for _yottadb.so, by running:
   
   ```shell
   $ ydb
   YDB>do &mlua.lua("return _VERSION")
   Lua 5.2
   YDB>do &mlua.lua("return package.cpath")
   <shows search path for _yottadb.so>
   ```
   
   Now test where Lua is trying to find your `_yottadb.so` by running `do &mlua.lua("print(package.cpath)")` (cf. environment variable LUA_CPATH). Note that these two files are typically located at:
   
   - /usr/local/lib/yottadb/r1??/plugin
   - /usr/local/lib/lua/5.?/_yottadb.so

