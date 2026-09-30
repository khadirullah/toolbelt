PREFIX ?= $(HOME)/.local
BATS ?= $(shell command -v bats 2>/dev/null || echo $(HOME)/.cache/toolbelt-dev/bats-core/bin/bats)
T ?=
D ?=

.PHONY: help install uninstall test lint man site check distro-test clean

help:
	@echo "make install     install to $(PREFIX), no sudo"
	@echo "make uninstall   remove what install put in place"
	@echo "make test        run every test, or one with T=unpack"
	@echo "make lint        shellcheck every script"
	@echo "make man         build man/man1 from docs"
	@echo "make site        build site/ from docs"
	@echo "make check       lint, test, and check the docs"
	@echo "make distro-test run CI's tests on every distro in Docker, or one with D=alpine:3"

install:
	./install.sh --prefix "$(PREFIX)"

uninstall:
	./install.sh --prefix "$(PREFIX)" --uninstall

test:
	$(BATS) $(if $(T),tests/$(T).bats,tests)

lint:
	shellcheck -x bin/* lib/common.sh lib/kube.sh shell/functions.sh install.sh completions/toolbelt.bash \
		tools/distro-test

man:
	python3 tools/md2man.py

site:
	python3 tools/build-site.py

check: lint test
	python3 tools/check-docs.py

distro-test:
	tools/distro-test $(D)

clean:
	rm -rf site/out
