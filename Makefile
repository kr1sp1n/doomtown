
help: ## Show help for this Makefile
	@grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | sort | awk 'BEGIN {FS = ":.*? ##"}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

update-fullmoon: ## Download latest fullmoon from repo
	wget https://raw.githubusercontent.com/pkulchenko/fullmoon/master/fullmoon.lua -P ./.lua/

build: ## Build server
	./bin/zip.com doomtown.com .init.lua schema.sql .lua/* views/* public/* public/*/*

docker-build: ## Build docker image
	docker build -t doomtown.cc .

docker-run: ## Run docker image
	docker run -it --rm -p "1980:1980" -v "./data:/data" -v "./files:/files" doomtown.cc

build-all: build docker-build

clean:
	rm -rf doomtown.db
	rm -rf files/uploaded

run:
	./doomtown.com -vv -X -D ./files