FROM python:3.6-alpine

COPY stream_processor/processor.py stream_processor/requirements.txt /
RUN apk update && \
    apk add ffmpeg gcc libc-dev && \
    pip install -r requirements.txt && \
    apk del --purge gcc libc-dev

CMD ["python", "processor.py"]
