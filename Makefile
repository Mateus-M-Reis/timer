.PHONY: test test-all lint fmt fmt-check

LUA_FILES = timer.lua init.lua main.lua

test:
	busted spec

test-all:
	busted spec
	busted --lua=luajit spec
	busted --lua=lua5.2 spec
	busted --lua=lua5.3 spec
	busted --lua=lua5.4 spec

lint:
	luacheck $(LUA_FILES) spec

fmt:
	stylua $(LUA_FILES) spec

fmt-check:
	stylua --check $(LUA_FILES) spec
