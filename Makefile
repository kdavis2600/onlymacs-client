SWIFT_APP_PATH := apps/onlymacs-macos
BRIDGE_PATH := apps/local-bridge
WEB_PATH := apps/onlymacs-web
COORDINATOR_PATH ?= $(if $(ONLYMACS_COORDINATOR_REPO),$(ONLYMACS_COORDINATOR_REPO),../OnlyMacs-coordinator)

.PHONY: bootstrap test test-public test-private test-all web-deps web-check public-preflight public-export coordinator-test dev stop-dev e2e-smoke local-smoke two-bridge-remote-smoke helper-binaries macos-app-public macos-pkg-public verify-macos-pkg-public signed-macos-pkg-public notarize-macos-pkg-public sign-macos-public verify-signed-macos-public signed-macos-dmg-public macos-dmg-public notarize-macos-dmg-public verify-macos-dmg-public release-readiness coordinator-scale-envelope app-bundle-smoke publish-onlymacs-update release-onlymacs

bootstrap:
	@swift package resolve --package-path $(SWIFT_APP_PATH)
	@cd $(BRIDGE_PATH) && go mod tidy
	@$(MAKE) web-deps
	@go work sync

test: test-public

test-public:
	@swift test --package-path $(SWIFT_APP_PATH)
	@cd $(BRIDGE_PATH) && go test ./...
	@find integrations scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
	@bash integrations/common/test-onlymacs-cli-intents.sh
	@bash scripts/qa/onlymacs-remote-work-contract-matrix.sh
	@bash scripts/qa/onlymacs-reporting-contract-matrix.sh
	@$(MAKE) web-check

test-private: coordinator-test

test-all: test-public test-private

web-deps:
	@cd $(WEB_PATH) && if [ ! -d node_modules ]; then npm ci; fi

web-check: web-deps
	@cd $(WEB_PATH) && npm run lint
	@cd $(WEB_PATH) && npm run build

public-preflight:
	@bash scripts/preflight-public-client.sh

public-export:
	@bash scripts/export-public-client.sh

coordinator-test:
	@cd $(COORDINATOR_PATH) && go test ./...

dev:
	@./scripts/make-dev.sh

stop-dev:
	@./scripts/stop-dev.sh

e2e-smoke:
	@./scripts/make-e2e-smoke.sh

local-smoke:
	@./scripts/make-local-smoke.sh

two-bridge-remote-smoke:
	@./scripts/make-two-bridge-remote-smoke.sh

helper-binaries:
	@./scripts/build-helper-binaries.sh

macos-app-public:
	@./scripts/build-macos-app-public.sh

macos-pkg-public:
	@./scripts/build-macos-pkg-public.sh

verify-macos-pkg-public:
	@./scripts/verify-macos-pkg-public.sh

signed-macos-pkg-public:
	@./scripts/build-macos-app-public.sh >/dev/null
	@./scripts/sign-macos-public.sh >/dev/null
	@ONLYMACS_REBUILD_APP=0 ONLYMACS_SIGN_APP_BEFORE_PKG=0 ./scripts/build-macos-pkg-public.sh >/dev/null
	@./scripts/verify-macos-pkg-public.sh

notarize-macos-pkg-public:
	@./scripts/notarize-macos-pkg-public.sh

sign-macos-public:
	@./scripts/sign-macos-public.sh

verify-signed-macos-public:
	@./scripts/verify-signed-macos-public.sh

macos-dmg-public:
	@./scripts/build-macos-dmg-public.sh

signed-macos-dmg-public:
	@./scripts/build-macos-app-public.sh >/dev/null
	@./scripts/sign-macos-public.sh >/dev/null
	@ONLYMACS_REBUILD_APP=0 ./scripts/build-macos-dmg-public.sh >/dev/null
	@./scripts/verify-macos-dmg-public.sh

notarize-macos-dmg-public:
	@./scripts/notarize-macos-dmg-public.sh

verify-macos-dmg-public:
	@./scripts/verify-macos-dmg-public.sh

release-readiness:
	@./scripts/check-release-readiness.sh

coordinator-scale-envelope:
	@./scripts/check-coordinator-scale-envelope.sh

app-bundle-smoke:
	@./scripts/make-app-bundle-smoke.sh

publish-onlymacs-update:
	@./scripts/publish-onlymacs-update.sh

release-onlymacs:
	@./scripts/release-onlymacs.sh
