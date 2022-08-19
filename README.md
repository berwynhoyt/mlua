# MLua - Lua for the MUMPS database

## Overview

MLua is a Lua language plugin the MUMPS database. It provides the means to call Lua from whitin M. Here is [more complete documentation](https://dev.anet.be/doc/brocade/mlua/html/index.html) of where this project is headed. MLua incorporates [lua-yottadb](https://github.com/orbitalquark/lua-yottadb/) so that Lua code written for that (per ydb's [Multi-Language Programmer's Guide](https://docs.yottadb.com/MultiLangProgGuide/luaprogram.html)) will also work with MLua.

Invoking a Lua command is easy:

```lua
$ ydb
YDB>do &mlua.lua("print('\nHello World!')")
Hello world!
```

Now let's access a ydb local. At the first print statement we'll intentionally create a Lua syntax error:

```lua
YDB>do &mlua.lua("ydb = require 'yottadb'")
YDB>set hello=$C(10)_"Hello World!"

YDB>write $&mlua.lua("print hello",.errorOutput)  ; print requires parentheses
-3
YDB>write errorOutput
Lua: [string "mlua(code)"]:1: syntax error near 'hello'

YDB>write $&mlua.lua("print(ydb.get('hello'))",.errorOutput)
Hello World!

0
YDB>write errorOutput

YDB>
```



### Example Lua task

Let's use Lua to calculate the height of your neighbour's oak trees based on the length of their shadow and the angle of the sun. First we enter the raw data into ydb, then run Lua to fetch from ydb and calculate:

```lua
YDB>set ^oaks(1,"shadow")=10,^("angle")=30
YDB>set ^oaks(2,"shadow")=13,^("angle")=30
YDB>set ^oaks(3,"shadow")=15,^("angle")=45

YDB>do &mlua.lua("print() ydb.dump('^oaks')") ;see definition of ydb.dump() below
^oaks("1","angle")="30"
^oaks("1","shadow")="10"
^oaks("2","angle")="30"
^oaks("2","shadow")="13"
^oaks("3","angle")="45"
^oaks("3","shadow")="15"

YDB>do &mlua.lua("dofile 'tree_height.lua'")  ; see file contents below
YDB>do &mlua.lua("print() show_oaks( ydb.key('^oaks') )")
Oak 1 is 5.8m high
Oak 2 is 7.5m high
Oak 3 is 15.0m high

YDB>zwr ^oaks(,"height")
^oaks(1,"height")=5.7735026918963
^oaks(2,"height")=7.5055534994651
^oaks(3,"height")="15.0"
```

Now let's write some Lua code to fetch data from ydb and calculate oak heights. Here's `oakheight.lua`:

```lua
function show_oaks(oakkey)
    for sub in oakkey:subscripts() do
        oak=oakkey(sub)
        height = oak('shadow').value * math.tan( math.rad(oak('angle').value) )

        print(string.format('Oak %s is %.1fm high', sub, height))
        oak('height').value = height  -- save back into ydb
    end
end
```

Further documentation of Lua's API for ydb is documented in ydb's [Multi-Language Programmer's Guide](https://docs.yottadb.com/MultiLangProgGuide/luaprogram.html).

### MLUA_INIT and ydb.dump()

Oh, so `ydb.dump()` doesn't work for you? That's because I cheated: I loaded the `ydb.dump()` function on startup by setting my environment variable `MLUA_INIT=@startup.lua` so that it runs the file below when &mlua.lua starts.  Just like Lua's standard LUA_INIT, set MLUA_INIT to Lua code, or to a filepath starting with @.

My `startup.lua` file defines ydb.dump():

```lua
local ydb = require 'yottadb'
function ydb.dump(glvn, ...)
  for node in ydb.nodes(tostring(glvn), ...) do
    print(string.format('%s("%s")=%q',
        glvn, table.concat(node, '","'), ydb.get(tostring(glvn), node)))
  end
end
```

You can add your own handy code at startup. For example, to avoid having to explicity require the ydb library every time you run ydb+mlua, just remove the word 'local' in the file above, or set `MLUA_INIT="ydb = require 'yottadb' "`

## API

Here is the list of supplied functions, [optional parameters in square brackets]:

- mlua.lua(code\[,.errstr]\[,luaState])
- mlua.open([.errstr])
- mlua.close(luaState)

When .errstr is supplied, it is cleared on success and filled with the error message on error.

If the luaState handle is missing or 0, mlua.lua() will run the code in the default global lua_State, automatically opening it the first time you call mlua.lua(). Alternatively, you can supply a luaState with a handle returned by mlua.open() to run code in a different lua_State.

Thread safety: A lua_State is not re-entrant, so if you use multiple ydb threads you will need to use mlua.open() to invoke Lua code in a separate state for each thread, or ensure in some other way that a thread does not re-enter a lua_State that another thread is currently running.

If you are finished using a lua_State, you may mlua.close(luaState) to free up any memory its code has allocated. This will also call any garbage-collection metamethods you have introduced.

## Versions & Acknolwledgements

MLua requires Lua version 5.2 or higher and ydb 1.34 or higher. Older Lua versions may work but are untested and would have to be built manually since the MLua Makefile does not know how to build them.

MLua's primary author is Berwyn Hoyt. MLua incorporates [lua-yottadb](https://github.com/orbitalquark/lua-yottadb/) (which is based heavily on YDBPython) by Mitchell Balan. Both were sponsored by, and are copyright © 2022, [University of Antwerp Library](https://www.uantwerpen.be/en/library/). They are provided under the same license as YottaDB: the [GNU Affero General Public License version 3](https://www.gnu.org/licenses/agpl-3.0.txt).

MLua also uses [Lua](https://www.lua.org/) (copyright © 1994–2021 Lua.org, PUC-Rio) and [YottaDB](https://yottadb.com/) (copyright © 2017-2019, YottaDB LLC). Both are available under open source licenses.

## Installation

1. Install YottaDB per the [Quick Start](https://docs.yottadb.com/MultiLangProgGuide/MultiLangProgGuide.html#quick-start) guide instructions or from [source](https://gitlab.com/YottaDB/DB/YDB).
2. git clone `<mlua repository>` mlua && cd mlua
3. make
4. sudo make install       # install MLua
5. sudo make install-lua   # optional, if you also want to install the Lua version you built here into your system

If you need to use a different Lua version or install into a non-standard YDB directory, change the last line to something like:

```shell
sudo make install LUA_BUILD_VERSION=5.x.x YDB_DEST=<your_ydb_plugin_directory> LUA_LIB_INSTALL=/usr/local/lib/lua/x.x LUA_MOD_INSTALL=/usr/local/share/lua/x.x
```

MLua is implemented as a shared library mlua.so which also embeds Lua and the Lua library. There is no need to install Lua separately.

### Explanation

Here's what is going on in the installation.
Line 2 fetches the MLua code and makes it the working directory.
Line 3 downloads and then builds the Lua language, then it builds MLua.
Line 4 installs mlua.xc and mlua.so, typically into $ydb_dist/plugin, and _yottadb.so and yottadb.lua into the system lua folders

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

## TESTING

Simply type:

```shell
make test
```
