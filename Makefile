APPS_DIR  ?= $(HOME)/Applications
BIN_DIR   ?= $(HOME)/.local/bin
AGENTS    := $(HOME)/Library/LaunchAgents
# A stable signing identity keeps the Accessibility grant across rebuilds; ad-hoc ("-") re-prompts each time.
SIGN_ID   ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID/ {print $$2; exit}')
ifeq ($(SIGN_ID),)
SIGN_ID   := -
endif

.PHONY: build test app install uninstall login-item caps-login-item no-login-item clean

build:
	swift build -c release

test:
	swift test

# $(call bundle,Name,executable,plist): build Name.app around .build/release/executable and sign it.
define bundle
	rm -rf $(1).app
	mkdir -p $(1).app/Contents/MacOS
	cp .build/release/$(2) $(1).app/Contents/MacOS/$(2)
	cp Resources/$(3) $(1).app/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" --identifier dev.zspace.$(1) $(1).app
endef

# $(call agent,Name,executable): launchd agent that starts Name.app at login.
define agent
	mkdir -p $(AGENTS)
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '<key>Label</key><string>dev.zspace.$(1)</string>' \
	  '<key>ProgramArguments</key><array><string>$(APPS_DIR)/$(1).app/Contents/MacOS/$(2)</string></array>' \
	  '<key>RunAtLoad</key><true/>' \
	  '<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>' \
	  '<key>StandardErrorPath</key><string>$(HOME)/Library/Logs/$(2).log</string>' \
	  '</dict></plist>' > $(AGENTS)/dev.zspace.$(1).plist
	launchctl bootout gui/$$(id -u) $(AGENTS)/dev.zspace.$(1).plist 2>/dev/null || true
	launchctl bootstrap gui/$$(id -u) $(AGENTS)/dev.zspace.$(1).plist
endef

app: build
	$(call bundle,ZSpace,zspace,Info.plist)
	$(call bundle,Caps,caps,Caps-Info.plist)
	@echo "built ZSpace.app and Caps.app (signed: $(SIGN_ID))"

install: app
	mkdir -p $(APPS_DIR) $(BIN_DIR)
	rm -rf $(APPS_DIR)/ZSpace.app $(APPS_DIR)/Caps.app
	cp -R ZSpace.app Caps.app $(APPS_DIR)/
	ln -sf $(APPS_DIR)/ZSpace.app/Contents/MacOS/zspace $(BIN_DIR)/zspace
	ln -sf $(APPS_DIR)/Caps.app/Contents/MacOS/caps $(BIN_DIR)/caps
	@echo "installed $(APPS_DIR)/ZSpace.app and $(APPS_DIR)/Caps.app; CLIs in $(BIN_DIR)"
	@echo "start: open $(APPS_DIR)/ZSpace.app $(APPS_DIR)/Caps.app   (grant Accessibility to each when asked)"

login-item:
	$(call agent,ZSpace,zspace)
	@echo "zspace now starts at login (log: ~/Library/Logs/zspace.log)"

caps-login-item:
	$(call agent,Caps,caps)
	@echo "Caps now starts at login (log: ~/Library/Logs/caps.log)"

no-login-item:
	for a in ZSpace Caps; do launchctl bootout gui/$$(id -u) $(AGENTS)/dev.zspace.$$a.plist 2>/dev/null; rm -f $(AGENTS)/dev.zspace.$$a.plist; done; true

uninstall: no-login-item
	-$(BIN_DIR)/zspace exit 2>/dev/null
	-pkill -x caps
	rm -rf $(APPS_DIR)/ZSpace.app $(APPS_DIR)/Caps.app $(BIN_DIR)/zspace $(BIN_DIR)/caps

clean:
	rm -rf .build ZSpace.app Caps.app
