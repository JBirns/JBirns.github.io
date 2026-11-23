# Everyday commands. Run them from this folder, e.g. `make preview`.

MSG ?= Update site

.PHONY: help build preview new publish clean

help:
	@echo "make preview                      build, serve at http://localhost:1313 and rebuild on save"
	@echo "make build                        build the site once into ./output"
	@echo "make new TITLE=\"My note\"           create a new note (add TAXON=Theorem etc. if you like)"
	@echo "make publish MSG=\"what changed\"    commit everything and push; GitHub rebuilds the live site"

build:
	forester build

preview:
	./scripts/preview.sh

new:
	./scripts/new.sh "$(TITLE)" "$(TAXON)"

publish:
	git add -A
	git commit -m "$(MSG)" || echo "Nothing new to commit."
	git push

clean:
	rm -rf output build _tmp
