.PHONY: all build prepare start commit stop clean

TAG := daas-0-guacd
CMD := /bin/bash -i

all: build


build: stop
	docker build -t $(TAG) .

start: build
	docker run -d --rm \
		-p 4822:4822 \
		-e GUACD_LOGLEVEL=trace \
		--name $(TAG) $(TAG)

commit: start
	docker kill $(TAG)

stop:
	-docker rm -f $(TAG)

clean: stop
	-docker rmi $(TAG)
