FROM node:8-alpine

COPY app.js /
COPY package.json /
COPY package-lock.json /
COPY public /public
RUN echo http://nl.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories && \
    apk add --no-cache git py2-singledispatch && \
    npm install

ARG OCR_HOST
ENV OCR_HOST=$OCR_HOST

EXPOSE 3000

CMD ["node", "app.js"]
