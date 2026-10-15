.PHONY: build dev demo test release
build:
	./scripts/build.sh
dev: build
	open build/Click.app
demo: build
	open build/Click.app --args --demo
test:
	swift test
release:
	./scripts/build.sh --zip
