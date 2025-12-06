DEFAULT ?= help
default: ${DEFAULT}
.PHONY: default

none    = \033[0m
bold    = \033[1m
black   = \033[1m\033[30m
red     = \033[1m\033[31m
green   = \033[1m\033[32m
yellow  = \033[1m\033[33m
blue    = \033[1m\033[34m
magenta = \033[1m\033[35m
cyan    = \033[1m\033[36m
white   = \033[1m\033[37m

help:: ## print help
	@echo "\n\
	  ${yellow}FOO             ${blue}${FOO}\n\
	  ${yellow}BAR             ${blue}${FOO}\n\
	  ${none}\
	  "
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n\n  make ${cyan}<target>${none}\n\n"}  \
	  /^[a-zA-Z_\/%$${}.-]+:.*?##/ { printf "\n  ${cyan}%-15s${none}%s\n", $$1, $$2 } \
	  /^## / { printf "  %-15s%s\n", "", substr($$0, 3) } \
	  /^##@/ { printf "\n${white}%s${none}\n", substr($$0, 5) } \
	' $(MAKEFILE_LIST)
.PHONY: help

## DEPS

install-deps: ## install dependencies
	luarocks install --local busted
	luarocks install --local inspect
.PHONY: install-deps

##@ Test

test: ## Run all tests
	busted
.PHONY: test

watch: ## Run tests in watch mode (requires entr or similar)
	find . -name "*.lua" | entr -c busted
.PHONY: watch
