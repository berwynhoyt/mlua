# Generic Lua Wrapper

## Overview

Bart has posited the idea of a generic wrapper that will enable M code to call Lua on *any* M-based platform (YDB, GT.M, IRIS, etc.). The idea is to use a generic interface such as the shell, files, pipes, or sockets, to make functions calls from M to Lua and vice versa. This functionality is expected to be hundreds or thousands of times slower, and so it will be used only as a fallback until something better could be implemented, if, for example, the current platform's C API ceased to be supported.

MLua and lua-yottadb do this same thing using a C API. But a C API is non-generic, given that a hypothetical M-based platform may not expose a C API. By contrast, access to the shell and pipes are standard M code, so using them could make access to Lua using completely standard M, albeit very slow.

## Proposal

Write a mechanism to perform 2-way remote procedure calls (RPCs) between two distinct processes, one M, and the other Lua. This might be done using one of the following mechanisms (beginning with the easiest to implement):

- Linux standard RPC (in linux: man rpc). Linux RPCs are non standard M: this is not possible without a POSIX plugin.
- Linux message queues (in linux: man mq_overview). Message quques are not standard M: this is not possible without a POSIX plugin
- Shell command line with stdio pipes. Shell spawning is not defined by standard M, however most M implementations define spawning as an extension.
- Sockets: access is not defined by standard M, however many M implementations allow sockets with implementation-specific syntax for the `OPEN` command.
- FIFOs: access is not defined by standard M, however many M implementations allow FIFOs using implementation-specific syntax for the `OPEN` command.
- Files: access IS standard M, however the syntax of the `OPEN` command varies between implementations.

### Portability

Unfortunately, the syntax for the OPEN command parameters are not fully specified by the M standard, so they vary between implementations. For example, [Reference Standard M](https://gitlab.com/Reference-Standard-M/rsm/-/blob/main/doc/language.adoc#user-content-open) requires an additional channel number as the first parameter, where YottaDB does not – both of these formats are permitted by the standard. However, a simple wrapper function around `OPEN` could hide this.

In summary, there is no way to implement RPCs using 100% portable M. However, they can be implemented using Standard-compliant M as follows:

- most simply, using linux RPCs, if a POSIX extension were assumed to be available on all M implementations, or,
- (without an extension) either by shell-spawning or using a file-like device – provided a compatibility wrapper function were permissible.

Furthermore, it is necessary to use read/write functions for each RPC call. This [will violate ACID principles](https://docs.yottadb.com/ProgrammersGuide/langfeat.html#key-considerations-writing-tp-code) if used within transactions. To retain ACID principles, all transactions would need to be coded in M, not in Lua, which limit the wrapper's usefulness.

### Speed

Typical time to execute a linux shell command is 2ms, which is approximately 1000 times the overhead of an MLua function call written in C (timed using YottaDB command `for i=1:1:10000 zsystem "true"`). This means that spawning a new process for each RPC command is not idea.

Typical time to write+read RPC-like data to/from a pipe is about 5 microseconds, which will make RPC calling overhead about 4x an MLua function call written in C (timed using YottaDB command `open pipe:(command="cat")::"PIPE" for i=1:1:1000000 use pipe write "abcdefghijklmnopqrstuvwxyz",! read line use $p`). In addition, accessing the database from Lua will be 5 times slower than MLua written in C, because there will probably be no way to implement cached subscript arrays (which sped things up about 5 times on average).

## Which functions must be implemented?

To make **MLua** generic will require implementing the following low-level function via the selected generic RPC mechanism:

| Function                                                | Description                                                  |
| ------------------------------------------------------- | ------------------------------------------------------------ |
| lua^mlua (code\[,.output]\[,luaState]\[,param1]\[,...]) | Run a string of Lua code, passing parameters and returning results |

Also required will be to make **lua-yottadb** generic, which will require implementing the following low-level functions via the generic RPC mechanism. Higher level functions written in Lua will then wrap these low-level functions:

| Function                                           | Description                                                  |
| -------------------------------------------------- | ------------------------------------------------------------ |
| get (varname[, subs[, ...\]])                      | Gets the value of a variable/node or nil if it has no data.  |
| delete (varname[, subs\][, ...], type)             | Deletes a node or tree of nodes.                             |
| set (varname[, subs\][, ...], value)               | Sets the value of a variable/node.                           |
| data (varname[, subs[, ...[, ...\]]])              | Returns information about a variable/node (except intrinsic variables). |
| lock_incr (varname[, subs[, ...[, timeout\]]])     | Attempts to acquire or increment a lock on a variable/node, waiting if requested. |
| lock_decr (varname[, subs[, ...\]])                | Decrements a lock on a variable/node, releasing it if possible. |
| tp ([transid\][, varnames], f[, ...])              | Initiates a transaction.                                     |
| subscript_next (varname[, subs[, ...\]])           | Returns the next subscript for a variable/node.              |
| subscript_previous (varname[, subs[, ...\]])       | Returns the previous subscript for a variable/node.          |
| node_next (varname[, subs[, ...\]])                | Returns the full subscript table of the next node after a variable/node. |
| node_previous (varname[, subs\])                   | Returns the full subscript table of the node prior to a variable/node. |
| lock ([node_specifiers[, timeout\]])               | Releases all locks held and attempts to acquire all requested locks, waiting if requested. |
| delete_excl (varnames)                             | Deletes trees of all local variables except the given ones.  |
| incr (varname[, subs[, increment\]])               | Increments the numeric value of a variable/node.             |
| str2zwr (s)                                        | Returns the zwrite-formatted version of the given string.    |
| zwr2str (s)                                        | Returns the string described by the given zwrite-formatted string. |
| cip (ci_handle, routine_name_handle, type_list, n) | Call an M routine.                                           |

**Note:** The above list does not include signal blocking functions, which are not possible to implement in M.

## Effort

### Generic MLua in M

The effort to implement a generic RPC interface is estimated as follows:

- 5d: Design, implement, debug, RPC interface using sockets or pipes. Examine mg_python for good ideas.
- 4d: Harden the RPC interface to handle socket/pipe closures communication errors, sync errors, and timeouts. Create test cases.
- 5d: Implement each of the functions listed above in their M and Lua components (equivalent to redesigning MLua and lua-yottadb from the ground up).
- 2d: Implement `cip()` to call M routines from Lua
- 3d: Run against existing lua-yottadb unit tests, debug
- 2d: Release and document

21+2 days in total (+2 days per supported database to customise and test).

### MLua in C for each mumps implementation

It appears that currently-supported MUMPS implementations all have a C interface (including: Yottadb, Intersystems IRIS, FreeM, MiniM). Thus, another path for generic compatibility would be to implement MLua as a C extension in multiple of these MUMPS implementations.

This method will be quick, By way of example, porting MLua from [YottaDB](https://docs.yottadb.com/ProgrammersGuide/extrout.html) to [IRIS](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=BXCI_using#BXCI_using_routines) call-in interface would involve:

- 1d: Create a common M wrapper for the call-out syntax, to make it identical between different databases
- 3d: Create Lua wrappers for call-ins to M
- 2d: implement cip() to call M routines from Lua
- 3d: Run against existing lua-yottadb unit tests, debug.
- 1d: Release and document

10 days in total, per supported database

## Conclusion

It is possible to make a generic M wrapper for Lua that uses remote procedure calls (RPCs) between an M process and a Lua process. An implementation could use **standard** M, but **not portable** M (though a single wrapper function could hide the portability problem).

However, the resulting RPC mechanism will have important limitations:

1. Functions used within transactions must be M and not Lua, otherwise ACID principles will be violated.
2. There is no standard way to block M signals while Lua code is running. This will be non-generic code or limit Lua functions to not use long-running OS calls. (Though it may be possible to avoid this in a non-portable way by spawning child processes in a separate process group).
3. It will be slower.
   - 5-10x: If implemented using a FIFO, the function call overhead for the wrapper will be approximately 5 to 10 times that of an MLua function call written in C. Plus database access from Lua will take 5 times as long.
   - 1000x: If implemented by a shell, the function call overhead for the wrapper will be approximately 1000 times that of an MLua function call written in C.

In short, a C implementation will take less time to develop, but will need to done for each new database. A generic implementation will take longer but will have limitations.

