PREFIX   ?= /usr/local
BINDIR    = $(PREFIX)/bin
LIBDIR    = $(PREFIX)/lib/omarchy-secureboot
HOOKDIR   = /etc/pacman.d/hooks
STATEDIR  = /var/lib/omarchy-secureboot
SYSTEMDDIR = /etc/systemd/system

.PHONY: install uninstall

install:
	install -Dm755 bin/omarchy-secureboot $(DESTDIR)$(BINDIR)/omarchy-secureboot
	install -Dm644 -t $(DESTDIR)$(LIBDIR)/ lib/*.sh
	install -d $(DESTDIR)$(HOOKDIR)
	sed 's|@BINDIR@|$(BINDIR)|g' hooks/zzz-omarchy-secureboot.hook > $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	chmod 644 $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	install -d $(DESTDIR)$(SYSTEMDDIR)
	sed 's|@BINDIR@|$(BINDIR)|g' systemd/omarchy-secureboot-watcher.service > $(DESTDIR)$(SYSTEMDDIR)/omarchy-secureboot-watcher.service
	chmod 644 $(DESTDIR)$(SYSTEMDDIR)/omarchy-secureboot-watcher.service
	install -Dm644 systemd/omarchy-secureboot-watcher.path $(DESTDIR)$(SYSTEMDDIR)/omarchy-secureboot-watcher.path
	install -d $(DESTDIR)$(STATEDIR)
	@if [ -z "$(DESTDIR)" ] && command -v systemctl >/dev/null 2>&1; then \
		systemctl daemon-reload; \
		systemctl enable --now omarchy-secureboot-watcher.path; \
	fi
	@echo
	@echo "Installed omarchy-secureboot to $(BINDIR)"
	@echo "Run: sudo omarchy-secureboot help"

uninstall:
	@if [ -z "$(DESTDIR)" ] && command -v systemctl >/dev/null 2>&1; then \
		systemctl disable --now omarchy-secureboot-watcher.path >/dev/null 2>&1 || true; \
	fi
	rm -f $(DESTDIR)$(BINDIR)/omarchy-secureboot
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -f $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	rm -f $(DESTDIR)$(SYSTEMDDIR)/omarchy-secureboot-watcher.service
	rm -f $(DESTDIR)$(SYSTEMDDIR)/omarchy-secureboot-watcher.path
	rm -rf $(DESTDIR)$(STATEDIR)
	@if [ -z "$(DESTDIR)" ] && command -v systemctl >/dev/null 2>&1; then \
		systemctl daemon-reload; \
	fi
	@echo "Uninstalled omarchy-secureboot"
