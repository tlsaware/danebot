# DANE TLSA-safe certbot wrapper

# Adjust these to suit the local system
# See ./configure

bindir = /usr/local/bin
cfgdir = /etc/default
mandir = /usr/local/share/man
sysdir = /lib/systemd/system
crondir = /etc/cron.weekly

mansect = 1
mansectname = User Commands
mansectdir = $(mandir)/man$(mansect)

bin = $(bindir)/danebot
cfg = $(cfgdir)/danebot
man = $(mansectdir)/danebot.1
cron = $(crondir)/danebot
service = $(sysdir)/danebot.service
timer = $(sysdir)/danebot.timer

#install_extra = install-systemd
#uninstall_extra = uninstall-systemd

#install_extra = install-cronjob
#uninstall_extra = uninstall-cronjob

prereqs = bash certbot perl openssl rsync readlink dirname basename find mktemp diff pod2man
prereqs_oneof = xxd hexdump
prereqs_perl = Net::DNS::Resolver Net::DNS::Packet Net::DNS::Header Net::DNS::RR Net::DNS::RR::TLSA

help:
	@echo "The following make targets are available:"
	@echo ""
	@echo "  help              - Show this information (default target)"
	@echo "  check             - Check the local system for prerequisites"
	@echo "  install           - Same as install-bin + install-cfg + install-man"
	@echo "  install-bin       - Install $(bin)"
	@echo "  install-cfg       - Install $(cfg)"
	@echo "  install-man       - Install $(man)"
	@echo "  install-systemd   - Install $(service), $(timer)"
	@echo "  install-cronjob   - Install $(cron)"
	@echo "  uninstall         - Same as uninstall-bin + uninstall-man"
	@echo "  uninstall-bin     - Uninstall $(bin)"
	@echo "  uninstall-cfg     - Uninstall $(cfg)"
	@echo "  uninstall-man     - Uninstall $(man)"
	@echo "  uninstall-systemd - Uninstall $(service), $(timer)"
	@echo "  uninstall-cronjob - Uninstall $(cron)"
	@echo "  systemd-enable    - Enable and start the systemd timer"
	@echo "  systemd-disable   - Disable the systemd timer"
	@echo "  purge             - Same as uninstall + uninstall-cfg"
	@echo "  man                 Create ./danebot.1"
	@echo "  clean             - Delete ./danebot.1"
	@echo "  ls                - Run ls -l for all installed files"
	@echo
	@echo 'Before installing, read INSTALL for more details.'
	@echo 'After installing, read "man danebot" for more details.'
	@echo

check:
	@fail=0; \
	for x in $(prereqs); \
	do \
		case "`which $$x 2>&1`" in /*) ;; *) echo "Error: $$x is required but is not installed"; fail=1;; esac; \
	done; \
	found=0; \
	for x in $(prereqs_oneof); \
	do \
		case "`which $$x 2>&1`" in /*) found=1;; esac; \
	done; \
	if [ $$found = 0 ]; then echo "Error: one of $(prereqs_oneof) is required but neither is installed"; fail=1; fi; \
	for x in $(prereqs_perl); \
	do \
		perldoc $$x >/dev/null 2>&1; \
		if [ $$? != 0 ]; then echo "Error: Perl module $$x is required but is not installed"; fail=1; fi; \
	done; \
	[ $$fail = 0 ] || exit 1

install-bin:
	@if [ ! -d "$(bindir)" ]; then echo "$(bindir) does not exist (adjust Makefile)"; exit 1; fi
	cp danebot "$(bin)"
	chmod 755 "$(bin)"

install-cfg:
	@if [ ! -d "$(cfgdir)" ]; then echo "$(cfgdir) does not exist (adjust Makefile)"; exit 1; fi
	@if [ -f "$(cfg)" ]; \
	then \
		echo "cp danebot.default $(cfg).dist"; \
		cp danebot.default "$(cfg).dist"; \
		chmod 644 "$(cfg).dist"; \
	else \
		echo "cp danebot.default $(cfg)"; \
		cp danebot.default "$(cfg)"; \
		chmod 644 "$(cfg)"; \
	fi

install-man: man
	@if [ ! -d "$(mansectdir)" ]; then echo "$(mansectdir) does not exist (adjust Makefile)"; exit 1; fi
	cp danebot.1 "$(man)"
	chmod 644 "$(man)"

man: danebot.1

danebot.1: danebot.1.pod
	sed 's/C</B</g' $< | pod2man --section='$(mansect)' --center='$(mansectname)' --name=DANEBOT --release=danebot --quotes=none > $@

install: install-bin install-cfg install-man $(install_extra)

uninstall-bin:
	[ ! -f "$(bin)" ] || rm $(bin)

uninstall-cfg:
	[ "`echo $(cfg)*`" = "$(cfg)*" ] || rm $(cfg)*

uninstall-man:
	[ "`echo $(man)*`" = "$(man)*" ] || rm $(man)*

uninstall: uninstall-bin uninstall-man $(uninstall_extra)

purge: uninstall uninstall-cfg

clean:
	[ ! -f danebot.1 ] || rm danebot.1

install-systemd:
	@if [ ! -d "$(sysdir)" ]; then echo "$(sysdir) does not exist (adjust Makefile)"; exit 1; fi
	cp danebot.service danebot.timer "$(sysdir)"
	chmod 644 "$(service)" "$(timer)"
	systemctl daemon-reload

uninstall-systemd: systemd-disable
	[ ! -f "$(service)" ] || rm $(service)
	[ ! -f "$(timer)" ] || rm $(timer)
	systemctl daemon-reload

install-cronjob:
	@if [ ! -d "$(crondir)" ]; then echo "$(crondir) does not exist (adjust Makefile)"; exit 1; fi
	printf "#!/bin/sh\n\nexec $(bin)\n\n" > "$(cron)"
	chmod 755 "$(cron)"

uninstall-cronjob:
	[ ! -f "$(cron)" ] || rm $(cron)

systemd-enable:
	@if systemctl is-enabled certbot.timer >/dev/null 2>&1; \
	then \
		echo "Refusing to enable danebot.timer while certbot.timer is enabled."; \
		echo "Please execute this then try again:"; \
		echo; \
		echo "    systemctl stop certbot.timer"; \
		echo "    systemctl disable certbot.timer"; \
		echo; \
		exit 1; \
	fi
	systemctl enable danebot.timer
	systemctl start danebot.timer

systemd-disable:
	-systemctl stop danebot.timer
	-systemctl disable danebot.timer

ls:
	@ls -l "$(bin)" "$(cfg)"* "$(man)"* "$(service)" "$(timer)" "$(cron)" 2>&-; exit 0

