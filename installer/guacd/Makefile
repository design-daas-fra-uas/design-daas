.PHONY: all build clean

TAG := daas-0-guacd
DOCKER := sudo docker

# Build image only
all: build

build:
	$(DOCKER) build -t $(TAG) .

clean:
	-$(DOCKER) rmi $(TAG)
