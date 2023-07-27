FROM node:20-alpine3.17 as build

RUN npm install -g @bitwarden/cli
RUN npm list -g

FROM alpine:3.17

COPY --from=build /usr/local/lib/node_modules/@bitwarden/cli/build/bw.js /usr/local/bin/bw
COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
