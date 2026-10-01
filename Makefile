APP := build/CC Translator.app

.PHONY: build run clean

build:
	./scripts/build-app.sh

run: build
	-pkill -x CCTranslator
	open "$(APP)"

clean:
	rm -rf .build build
