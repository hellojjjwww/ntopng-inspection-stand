COMPOSE_FILE ?= deploy/docker-compose.yml
DESKTOP_COMPOSE_FILE ?= deploy/docker-compose.desktop.yml
USE_DESKTOP_OVERRIDE ?= 0
SERVICE ?=

ifeq ($(USE_DESKTOP_OVERRIDE),1)
COMPOSE = docker compose -f $(COMPOSE_FILE) -f $(DESKTOP_COMPOSE_FILE)
else
COMPOSE = docker compose -f $(COMPOSE_FILE)
endif

.PHONY: up down restart ps logs config test doctor evidence backup pull russian-ui

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart $(SERVICE)

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=200 $(SERVICE)

config:
	$(COMPOSE) config --quiet

test:
	USE_DESKTOP_OVERRIDE=$(USE_DESKTOP_OVERRIDE) deploy/scripts/tests/validate_stack.sh

doctor:
	USE_DESKTOP_OVERRIDE=$(USE_DESKTOP_OVERRIDE) scripts/doctor.sh

evidence:
	USE_DESKTOP_OVERRIDE=$(USE_DESKTOP_OVERRIDE) deploy/scripts/tests/collect_evidence.sh

backup:
	scripts/backup.sh

pull:
	$(COMPOSE) pull

russian-ui:
	USE_DESKTOP_OVERRIDE=$(USE_DESKTOP_OVERRIDE) scripts/enable_russian_ui.sh
