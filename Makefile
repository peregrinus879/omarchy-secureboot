PREFIX   ?= /usr/local
BINDIR    = $(PREFIX)/bin
LIBDIR    = $(PREFIX)/lib/omarchy-secureboot
HOOKDIR   = /etc/pacman.d/hooks

.PHONY: install uninstall

install:
	install -Dm755 bin/omarchy-secureboot $(DESTDIR)$(BINDIR)/omarchy-secureboot
	install -Dm644 -t $(DESTDIR)$(LIBDIR)/ lib/*.sh
	install -Dm644 hooks/zzz-omarchy-secureboot.hook $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	@echo
	@echo "Installed omarchy-secureboot to $(BINDIR)"
	@echo "Run: sudo omarchy-secureboot help"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/omarchy-secureboot
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -f $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	@echo "Uninstalled omarchy-secureboot"
