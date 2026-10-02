APP := build/Slovo.app

.PHONY: build run release clean

build:
	./scripts/build-app.sh

run: build
	-pkill -x Slovo
	open "$(APP)"

release:
	./scripts/release.sh

clean:
	rm -rf .build build
