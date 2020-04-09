HUGO=hugo

build:
	$(HUGO)

dev-serve:
	$(HUGO) serve --baseUrl localhost
