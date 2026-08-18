PREFIX   ?= /usr/local
BINDIR    = $(PREFIX)/bin
LIBDIR    = $(PREFIX)/lib/omasecboot
HOOKDIR   = /etc/pacman.d/hooks
LIMINEHOOKDIR = /etc/boot/hooks/post.d
STATEDIR  = /var/lib/omasecboot
LEGACY_LIBDIR   = $(PREFIX)/lib/omarchy-secureboot
LEGACY_STATEDIR = /var/lib/omarchy-secureboot

.PHONY: install uninstall test

install:
	install -Dm644 -t $(DESTDIR)$(LIBDIR)/ lib/*.sh
	install -d $(DESTDIR)$(STATEDIR)
	@if [ ! -e "$(DESTDIR)$(STATEDIR)/windows-enabled" ] \
	    && [ ! -L "$(DESTDIR)$(STATEDIR)/windows-enabled" ] \
	    && [ -f "$(DESTDIR)$(LEGACY_STATEDIR)/windows-enabled" ] \
	    && [ ! -L "$(DESTDIR)$(LEGACY_STATEDIR)/windows-enabled" ]; then \
		install -m 644 "$(DESTDIR)$(LEGACY_STATEDIR)/windows-enabled" "$(DESTDIR)$(STATEDIR)/windows-enabled"; \
	fi
	install -Dm755 bin/omasecboot $(DESTDIR)$(BINDIR)/omasecboot
	install -d $(DESTDIR)$(HOOKDIR)
	sed 's|@BINDIR@|$(BINDIR)|g' pacman-hooks/zz-omasecboot-cleanup.hook > $(DESTDIR)$(HOOKDIR)/zz-omasecboot-cleanup.hook
	chmod 644 $(DESTDIR)$(HOOKDIR)/zz-omasecboot-cleanup.hook
	sed 's|@BINDIR@|$(BINDIR)|g' pacman-hooks/zzz-omasecboot.hook > $(DESTDIR)$(HOOKDIR)/zzz-omasecboot.hook
	chmod 644 $(DESTDIR)$(HOOKDIR)/zzz-omasecboot.hook
	install -d $(DESTDIR)$(LIMINEHOOKDIR)
	sed 's|@BINDIR@|$(BINDIR)|g' limine-hooks/zzz-omasecboot-sign > $(DESTDIR)$(LIMINEHOOKDIR)/zzz-omasecboot-sign
	chmod 755 $(DESTDIR)$(LIMINEHOOKDIR)/zzz-omasecboot-sign
	rm -f $(DESTDIR)$(HOOKDIR)/zz-omarchy-secureboot-cleanup.hook
	rm -f $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	rm -f $(DESTDIR)$(LIMINEHOOKDIR)/zzz-omarchy-secureboot-sign
	rm -f $(DESTDIR)$(BINDIR)/omarchy-secureboot
	rm -rf $(DESTDIR)$(LEGACY_LIBDIR)
	rm -rf $(DESTDIR)$(LEGACY_STATEDIR)
	@echo
	@echo "Installed omasecboot to $(BINDIR)"
	@echo "Run: sudo omasecboot help"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/omasecboot
	rm -f $(DESTDIR)$(BINDIR)/omarchy-secureboot
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -rf $(DESTDIR)$(LEGACY_LIBDIR)
	rm -f $(DESTDIR)$(HOOKDIR)/zz-omasecboot-cleanup.hook
	rm -f $(DESTDIR)$(HOOKDIR)/zzz-omasecboot.hook
	rm -f $(DESTDIR)$(LIMINEHOOKDIR)/zzz-omasecboot-sign
	rm -f $(DESTDIR)$(HOOKDIR)/zz-omarchy-secureboot-cleanup.hook
	rm -f $(DESTDIR)$(HOOKDIR)/zzz-omarchy-secureboot.hook
	rm -f $(DESTDIR)$(LIMINEHOOKDIR)/zzz-omarchy-secureboot-sign
	rm -rf $(DESTDIR)$(STATEDIR)
	rm -rf $(DESTDIR)$(LEGACY_STATEDIR)
	@echo "Uninstalled omasecboot"

test:
	bash tests/install.sh
	bash tests/windows.sh
	bash tests/windows-migration.sh
