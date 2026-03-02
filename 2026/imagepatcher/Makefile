BIN := imagepatcher
IMAGE := imagepatcher:latest

.PHONY: build image run

build:
	go build -o $(BIN) .

image:
	docker build -t $(IMAGE) .

run:
	go run .
