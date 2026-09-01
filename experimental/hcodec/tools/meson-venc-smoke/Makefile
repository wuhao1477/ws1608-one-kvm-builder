CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -Wall -Wextra -Werror -std=c11

.PHONY: all check clean

all: meson-venc-smoke

meson-venc-smoke: meson-venc-smoke.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS)

check: meson-venc-smoke
	./meson-venc-smoke --help >/dev/null

clean:
	$(RM) meson-venc-smoke
