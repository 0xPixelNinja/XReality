PROXY_CONTAINER=xreality-proxy
PANEL_CONTAINER=xreality-panel

.PHONY: up down build logs restart \
        client-show client-link client-qr client-json regenerate

up:
	@cp -n .env.example .env 2>/dev/null || true
	docker compose up -d --build

down:
	docker compose down

build:
	docker compose build --no-cache

restart:
	docker compose restart

logs:
	docker compose logs -f

logs-proxy:
	docker logs -f $(PROXY_CONTAINER)

logs-panel:
	docker logs -f $(PANEL_CONTAINER)

client-show:
	docker exec $(PROXY_CONTAINER) bash ./client-config.sh show

client-link:
	docker exec $(PROXY_CONTAINER) bash ./client-config.sh link

client-qr:
	docker exec $(PROXY_CONTAINER) bash ./client-config.sh qr

client-json:
	docker exec $(PROXY_CONTAINER) bash ./client-config.sh json

regenerate:
	docker exec $(PROXY_CONTAINER) bash ./client-config.sh regenerate
	docker restart $(PROXY_CONTAINER)

clean:
	docker compose down -v --rmi local

