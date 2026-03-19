PREFIX   ?= /usr/local
BINDIR    = $(PREFIX)/bin
LIBDIR    = $(PREFIX)/lib/omarchy-secureboot
HOOKDIR   = /etc/pacman.d/hooks
STATEDIR  = /var/lib/omarchy-secureboot

.PHONY: install uninstall

install:
	install -Dm755 bin/omarchy-secureboot $(DESTDIR)$(BINDIR)/omarchy-secureboot
	install -Dm644 -t $(DESTDIR)$(LIBDIR)/ lib/*.sh
	install -d $(DESTDIR)$(HOOKDIR)
	sed 's|@BINDIR@|$(BINDIR)|g' hooks/zzz-omarchy-secureboot.hook > $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	chmod 644 $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	install -d $(DESTDIR)$(STATEDIR)
	@echo
	@echo "Installed omarchy-secureboot to $(BINDIR)"
	@echo "Run: sudo omarchy-secureboot help"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/omarchy-secureboot
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -f $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	rm -rf $(DESTDIR)$(STATEDIR)
	@echo "Uninstalled omarchy-secureboot"
