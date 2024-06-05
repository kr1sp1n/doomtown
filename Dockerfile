FROM alpine:latest as build
WORKDIR /app

RUN apk add --update zip bash

COPY doomtown.com ./

# normalize the binary to ELF
RUN sh ./doomtown.com --assimilate

# Add your files here
# COPY assets /app
# WORKDIR /app
# RUN zip -r /redbean.com *

FROM scratch
COPY --from=build /app/doomtown.com /
CMD ["/doomtown.com", "-vv", "-p", "1980", "-X", "-*", "-D", "/files"]
