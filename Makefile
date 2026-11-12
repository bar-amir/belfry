APP := build/Build/Products/Release/Belfry.app

.PHONY: project build run install icon clean

project:
	xcodegen generate

build: project
	xcodebuild -project Belfry.xcodeproj -scheme Belfry -configuration Release -derivedDataPath build build

run: build
	open $(APP)

install: build
	rm -rf /Applications/Belfry.app && cp -R $(APP) /Applications/

icon:
	swift scripts/make-icon.swift Belfry/Resources/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf build Belfry.xcodeproj
