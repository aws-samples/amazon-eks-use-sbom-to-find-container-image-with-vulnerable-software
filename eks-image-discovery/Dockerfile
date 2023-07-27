FROM public.ecr.aws/docker/library/python:3.12-rc-alpine

WORKDIR /app

COPY requirements.txt requirements.txt

RUN pip install --upgrade pip
RUN pip3 install -r requirements.txt

COPY . .

CMD ["python3", "-m" , "main"]