NAME = zeroae/ap-daas
VERSION = 0.1.0

.PHONY: all build build-nocache down up run

all: run

build:
	docker-compose -f local-compose.yml build
	docker build -t $(NAME) --rm .

build-nocache:
	docker build -t $(NAME) --no-cache --rm .

down:
	docker-compose -f local-compose.yml down --rmi local --remove-orphans

up: build
	docker-compose -f local-compose.yml up -d --build --remove-orphans

run: up
	docker-compose -f local-compose.yml scale daas=0
	docker-compose -f local-compose.yml scale daas=1
