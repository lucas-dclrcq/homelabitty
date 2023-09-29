FROM node:20.8-bookworm as build

WORKDIR /app

COPY package.json /app
RUN npm install

COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
