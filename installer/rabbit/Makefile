.PHONY: all build clean

TAG := daas-0-rabbit
DOCKER := sudo docker

all: build

build:
	$(DOCKER) build -t $(TAG) .

clean: 
	-$(DOCKER) rmi $(TAG)
	rm -rf noweb


