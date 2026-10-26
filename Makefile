.PHONY: up down validate

up:
	scripts/up.sh

down:
	kind delete cluster --name forge

validate:
	scripts/validate.sh
