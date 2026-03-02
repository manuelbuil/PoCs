BINARY ?= rke2-patcher
COMPONENT ?= traefik

.PHONY: help build version image-cve image-list image-patch

help:
	@echo "Targets:"
	@echo "  make build"
	@echo "  make version"
	@echo "  make image-cve COMPONENT=traefik"
	@echo "  make image-list COMPONENT=traefik"
	@echo "  make image-patch COMPONENT=traefik"

build:
	go build -o $(BINARY) .

version: build
	./$(BINARY) --version

image-cve: build
	./$(BINARY) image-cve $(COMPONENT)

image-list: build
	./$(BINARY) image-list $(COMPONENT)

image-patch: build
	./$(BINARY) image-patch $(COMPONENT)
