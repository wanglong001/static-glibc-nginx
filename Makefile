# Author: Eric Pruitt (http://www.codevat.com)
# License: 2-Clause BSD (http://opensource.org/licenses/BSD-2-Clause)
# Description: This Makefile is designed to create a statically linked nginx
#       binary without any dependencies on the host system's version of glibc.
.POSIX:

NGINX_TAR_GZ = http://nginx.org/download/nginx-1.19.10.tar.gz
OPENSSL_TAR_GZ = https://www.openssl.org/source/openssl-1.1.1j.tar.gz
PCRE_TAR_GZ = https://ftp.pcre.org/pub/pcre/pcre-8.44.tar.gz
ZLIB_TAR_GZ = http://zlib.net/zlib-1.2.11.tar.gz
MUSL_TAR_GZ = https://musl.libc.org/releases/musl-1.2.2.tar.gz

WGET = wget --no-use-server-timestamps

all: nginx/.FOLDER

clean:
	rm -rf .*-patched src pcre openssl nginx zlib musl

cleaner: clean
	rm -f nginx.tar.gz pcre.tar.gz openssl.tar.gz zlib.tar.gz musl.tar.gz

nginx.tar.gz:
	$(WGET) -O $@ $(NGINX_TAR_GZ)


src: nginx.tar.gz
	tar -x -z -f $?
	mv nginx-*/ $@
	touch $@

src/.PATCHED: src/src/core/nginx.c
#	(cd src && patch -p1 < ../static-glibc-nginx.patch)
	touch $@

src/src/core/nginx.c: src

pcre.tar.gz:
	$(WGET) -O $@ $(PCRE_TAR_GZ)

pcre/.FOLDER: pcre.tar.gz
	tar -x -z -f $?
	mv pcre*/ $(@D)
	touch $@

musl.tar.gz:
	$(WGET) -O $@ $(MUSL_TAR_GZ)


musl/.FOLDER: musl.tar.gz
	tar -x -z -f $?
	mv musl*/ $(@D)
	touch $@
	cd $(@D) && ./configure && make install

CC = /usr/local/musl/bin/musl-gcc

openssl.tar.gz:
	$(WGET) -O $@ $(OPENSSL_TAR_GZ)

openssl/.FOLDER: openssl.tar.gz
	tar -x -z -f $?
	mv openssl*/ $(@D)
	touch $@

zlib.tar.gz:
	$(WGET) -O $@ $(ZLIB_TAR_GZ)

zlib/.FOLDER: zlib.tar.gz
	tar -x -z -f $?
	mv zlib-*/ $(@D)
	touch $@

src/Makefile: openssl/.FOLDER pcre/.FOLDER src/.PATCHED zlib/.FOLDER musl/.FOLDER
	(cd src && \
	./configure \
		--conf-path=nginx.conf \
		--pid-path=nginx.pid \
		--prefix=. \
		--sbin-path=. \
		--with-cc="$(CC)" \
		--with-cc-opt="$(CFLAGS) -static -D NGX_HAVE_DLOPEN=0" \
		--with-cpu-opt=generic \
		--with-http_addition_module \
		--with-http_auth_request_module \
		--with-http_dav_module \
		--with-http_degradation_module \
		--with-http_flv_module \
		--with-http_gunzip_module \
		--with-http_gzip_static_module \
		--with-http_mp4_module \
		--with-http_random_index_module \
		--with-http_realip_module \
		--with-http_secure_link_module \
		--with-http_ssl_module \
		--with-http_stub_status_module \
		--with-http_sub_module \
		--with-http_v2_module \
		--with-ipv6 \
		--with-ld-opt="$(LDFLAGS) -static" \
		--with-mail \
		--with-mail_ssl_module \
		--with-openssl-opt="-UDSO_DLFCN" \
		--with-openssl=../openssl \
		--with-pcre=../pcre \
		--with-poll_module \
		--with-select_module \
		--with-zlib="../zlib" \
	)

src/objs/nginx: src/Makefile
	(cd src && $(MAKE))

nginx/.FOLDER: src/objs/nginx
	mkdir -p $(@D)
	(cd src && $(MAKE) DESTDIR=$(PWD)/$(@D)/ install)
	(cd $(@D) && rm -f *.default koi-win koi-utf win-utf)
	touch $@

test:
	@./nginx/nginx -c "$$PWD/test.conf" -e /dev/fd/1 -p nginx & \
	nginx_pid="$$!" && \
	trap 'kill "$$nginx_pid"; rm -rf nginx/*_temp/' EXIT && \
	(sleep 0.05 >/dev/null 2>&1 || :) && \
	if ! kill -1 "$$nginx_pid"; then \
		echo "make $@: unable to start nginx" >&2; \
		exit 1; \
	fi; \
	for _ in 1 2 3; do \
		nc -zw1 localhost 4475 && break; \
		sleep 1; \
	done; \
	curl -fsS http://localhost:4475/ >/dev/null || exit_status="$$?" && \
	exit "$${exit_status:-0}"
	@echo "make $@: test passed"
