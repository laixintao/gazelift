.DEFAULT_GOAL := help
.PHONY: help build test package ci check ci-package release release-validate release-verify release-publish
export VERSION RELEASE_TAG ARTIFACT_DIR

help:
	@printf '%s\n' 'make build       Build GazeLift.app (Command Line Tools only)' 'make test        Run state, settings, and native UI tests' 'make package     Package a universal DMG and ZIP' 'make ci          Validate, test, and package' 'make release     Prepare and atomically push the next release' 'make release VERSION=0.2.0  Release an explicit version'
build:
	bash scripts/build.sh Release native
test:
	bash scripts/test.sh
check:
	python3 scripts/check-project.py
	python3 -m unittest discover -s Tests -p 'test_*.py' -v
package:
	bash scripts/build.sh Release universal
	bash scripts/package.sh
	bash scripts/verify-package.sh
ci: check test package
ci-package: ci
release:
	python3 scripts/release.py
release-validate:
	python3 scripts/check-project.py --release-tag "$(RELEASE_TAG)"
release-verify:
	bash scripts/verify-package.sh
release-publish:
	python3 scripts/publish-release.py
