.DEFAULT_GOAL := test

.PHONY: build
build:
	dune build

.PHONY: run
run:
	dune exec ./bin/main.exe -- $(ARGS)

.PHONY: test
test:
	dune runtest

.PHONY: clean
clean:
	dune clean
