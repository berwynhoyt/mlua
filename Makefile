# Makefile to build MLua

CC=gcc

YDB_DIST=$(shell pkg-config --variable=prefix yottadb)

CFLAGS=-std=c99 -pedantic -Wall -Wno-unknown-pragmas
YDB_FLAGS=$(shell pkg-config --cflags yottadb)

FETCH_LIBREADLINE=$(if $(shell which apt-get), sudo apt-get install libreadline-dev, sudo yum install readline-devel)

all: build

build: mlua.so

try: try.c
	$(CC) $< -o $@  $(YDB_FLAGS) $(CFLAGS)

mlua.o: mlua.c
	$(CC) $<  -c -fPIC $(YDB_FLAGS) $(CFLAGS)

mlua.so: mlua.o
	$(CC) $< -o $@  -shared

# Fetch lua builds if necessary
lua: lua5.4 lua5.3 lua5.2
lua5.4: externals/lua-5.4.4/src/lua
lua5.3: /usr/include/readline/readline.h externals/lua-5.3.6/src/lua
lua5.2: /usr/include/readline/readline.h externals/lua-5.2.4/src/lua

externals/lua-%/src/lua: externals/lua-%/Makefile
	@echo Building $@
	make --directory=externals/lua-$* linux test
	@echo

externals/lua-%/Makefile:
	@echo Fetching $@
	mkdir -p $@
	wget --directory-prefix=externals --no-verbose "http://www.lua.org/ftp/lua-$*.tar.gz" -O $@.tar.gz
	tar --directory=externals -zxf $@.tar.gz
	rm -f $@.tar.gz
	@echo

/usr/include/readline/readline.h:
	@echo "Installing readline development library required by builds of lua <5.4
	$(FETCH_LIBREADLINE)

# clean just our build
clean:
	rm -f *.o *.so try
	rm -rf tests

# clean externals (e.g. lua), too
clean-all: clean
	rm -rf externals

test:
	mkdir -p tests
	python3 test.py
	env ydb_routines="./tests $(ydb_routines)" ydb -run "^tests"

install: mlua.so mlua.xc
	sudo cp mlua.so mlua.xc $(YDB_DIST)/plugin

.PHONY: install test clean clean-all lua build
