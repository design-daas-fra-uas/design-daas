.PHONY: all prepare build ensureKey start commit stop clean clean-all

TAG := daas-0-extensions
CMD := /bin/bash -i
HOSTIP := 0.0.0.0
BUILDOPT?=

all: commit

ensureKey:
	if [ ! -f ./VNCService/id_rsa.pub ] ; then \
		cp /root/.ssh/id_rsa.pub ./VNCService/id_rsa.pub ; \
	fi

build: | stop ensureKey
	cd VNCService && sudo docker build $(BUILDOPT) -t $(TAG) .

start: build
	sudo docker run -d \
                --security-opt apparmor=unconfined \
		-p "$(HOSTIP):631:631" \
		-p "$(HOSTIP):8010:8010" \
		-p "$(HOSTIP):8020:8020" \
		--name $(TAG) $(TAG)

commit: start
	sudo docker commit $(TAG)
	sudo docker kill $(TAG)

stop:
	-sudo docker rm -f $(TAG)

clean: stop
	-sudo docker rmi $(TAG)
