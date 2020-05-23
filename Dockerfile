#Comment
FROM python:stretch

COPY . /app
WORKDIR /app

RUN pip install --upgrade pip
RUN pip install -r requirements.txt

ENTRYPOINT ["gunicorn","-b",":8090","main:APP"]
