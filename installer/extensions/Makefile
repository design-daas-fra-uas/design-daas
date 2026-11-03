.PHONY: all build ensureKey clean

TAG := daas-0-extensions
BUILDOPT?=
DOCKER := sudo docker

all: build

ensureKey:
	if [ ! -f ./VNCService/id_rsa.pub ] ; then \
		cp /root/.ssh/id_rsa.pub ./VNCService/id_rsa.pub ; \
	fi

build: ensureKey
	cd VNCService && $(DOCKER) build $(BUILDOPT) -t $(TAG) .

clean:
	-$(DOCKER) rmi $(TAG)


