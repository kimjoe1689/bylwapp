.PHONY: server-test server-build server-run app-analyze app-test worker-test

server-test:
	$(MAKE) -C server test

server-build:
	$(MAKE) -C server build

server-run:
	$(MAKE) -C server run

app-analyze:
	cd app && flutter analyze

app-test:
	cd app && flutter test

worker-test:
	cd worker && npm test
