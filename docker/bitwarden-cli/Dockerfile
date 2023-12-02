FROM node:21.3-bookworm as build

WORKDIR /app

COPY package.json /app
RUN npm install

COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
