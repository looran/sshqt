PREFIX=/usr/local
BINDIR=$(PREFIX)/bin

all:
	@echo "Run \"sudo make install\" to install sshqt"

install:
	install -m 0755 sshqt.sh $(BINDIR)/sshqt

