FROM alpine:3.21.0
WORKDIR /doomtown

RUN apk add --update --no-cache tcl tcl-lib sqlite-tcl tini

COPY src/wapp.tcl ./
COPY src/main.tcl ./
COPY src/utils.tcl ./
COPY src/schema.sql ./

ENV PORT 8080
ENV ADMIN_KEY ""

ENTRYPOINT ["/sbin/tini", "--"]

CMD tclsh main.tcl --port $PORT --admin_key $ADMIN_KEY