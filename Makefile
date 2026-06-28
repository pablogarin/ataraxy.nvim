.PHONY: test lint all

all: test

test:
	nvim --headless -u scripts/minimal_init.lua -c "lua MiniTest.run()" -c "qa!"

lint:
	luacheck lua/ tests/
