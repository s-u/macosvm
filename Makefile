mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
mkfile_dir := $(dir $(mkfile_path))

local_bin = /usr/local/bin/
name = macosvm

path := $(local_bin)$(name)

build:
	make -C $(name) $(name)

$(local_bin):
	@test -d $(local_bin) || ( \
		echo "$(local_bin) does not exist (may happen on Apple Silicon setups). Attempting to create [sudo will be required]" && \
		sudo mkdir  $(local_bin) && \
		echo "Done" )

$(path): $(local_bin) build
	cd  $(mkfile_dir)$(name) && \
		chmod a+x ./$(name)	&& \
		sudo cp -f ./$(name) $(local_bin) 
	@echo $(name) installed and ready for use.
clean:
	make -C $(name) clean

uninstall:
	sudo rm -f $(path)

install:  $(path)

.PHONY: all install uninstall

all: build install 
