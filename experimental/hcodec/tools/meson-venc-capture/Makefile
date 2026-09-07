# SPDX-License-Identifier: GPL-2.0-only

CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -Wall -Wextra -Werror -std=c11

all: meson-venc-capture

meson-venc-capture: meson-venc-capture.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS)

check: meson-venc-capture
	./meson-venc-capture --help >/dev/null

clean:
	$(RM) meson-venc-capture

.PHONY: all check clean
