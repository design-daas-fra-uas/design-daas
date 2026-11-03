.PHONY: all prepare build start commit stop clean clean-all

TAG := daas-0-rabbit
CMD := /bin/bash -i
HOSTIP := 172.17.0.1
DOCKER := sudo docker

all: commit

build: stop
	$(DOCKER) build -t $(TAG) .

start: build
	$(DOCKER) run -d \
                --security-opt apparmor=unconfined \
		-p $(HOSTIP):4369:4369 \
		-e RABBITMQ_HEARTBEAT=30 \
		-p $(HOSTIP):5672:5672 \
		--name $(TAG) --restart unless-stopped $(TAG)

commit: start
	$(DOCKER) commit $(TAG)

stop:
	-$(DOCKER) rm -f $(TAG)

clean: stop
	-$(DOCKER) rmi $(TAG)
	rm -rf noweb

