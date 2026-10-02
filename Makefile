APP := build/Slovo.app

.PHONY: build run clean

build:
	./scripts/build-app.sh

run: build
	-pkill -x Slovo
	open "$(APP)"

clean:
	rm -rf .build build
