NAME = zeroae/ap-daas
VERSION = 0.1.0

MANTA_PRIVATE_KEY_PATH=~/.ssh/id_rsa

.PHONY: all build build-nocache down up run

all: run

build:
	docker-compose -f local-compose.yml build
	docker build -t $(NAME) --rm .

build-nocache:
	docker build -t $(NAME) --no-cache --rm .

down:
	docker-compose -f local-compose.yml down --rmi local --remove-orphans

up: build .env
	docker-compose -f local-compose.yml up -d --build --remove-orphans

run: up
	docker-compose -f local-compose.yml scale daas=0
	docker-compose -f local-compose.yml scale daas=1

.env:
	@echo "# Environment variables for backups to Manta" >> .env
	@echo "MANTA_URL=https://us-east.manta.joyent.com" >> .env
	@echo "MANTA_BUCKET= # an existing Manta bucket" >> .env
	@echo "MANTA_USER=" >> .env
	@echo "MANTA_SUBUSER=" >> .env
	@echo "MANTA_ROLE=" >> .env
	@ssh-keygen -yl -E md5 -f $(MANTA_PRIVATE_KEY_PATH) > /dev/null 2>&1 && \
	if [ $$? -eq 0 ]; then \
		echo MANTA_KEY_ID=$$(ssh-keygen -yl -E md5 -f $(MANTA_PRIVATE_KEY_PATH) | awk '{print substr($$2,5)}') >> .env; \
	else \
		echo MANTA_KEY_ID=$$(ssh-keygen -yl -f $(MANTA_PRIVATE_KEY_PATH) | awk '{print $$2}') >> _env; \
	fi
	@echo MANTA_PRIVATE_KEY=$$(cat $(MANTA_PRIVATE_KEY_PATH) | tr '\n' '#') >> .env
	@echo >> .env
