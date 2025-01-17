DOCKER?=docker
DC?=docker-compose

help: ## Show help for this Makefile
	@grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | sort | awk 'BEGIN {FS = ":.*? ##"}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

build: ## Build docker image
	${DOCKER} build --no-cache -t kr1sp1n/doomtown .

up: ## Run local with docker-compose
	${DC} up