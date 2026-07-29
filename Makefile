SHELL := /bin/bash

.PHONY: check syntax shellcheck test

check: syntax shellcheck test

syntax:
	bash -n zrb.sh parallel-zrb.sh zrb-client.sh $$(find lib test -type f -name '*.sh' -print)

shellcheck:
	shellcheck -x zrb.sh parallel-zrb.sh zrb-client.sh $$(find lib test -type f -name '*.sh' -print)

test:
	bash test/run.sh
