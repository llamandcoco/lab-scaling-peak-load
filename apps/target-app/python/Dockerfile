FROM public.ecr.aws/amazonlinux/amazonlinux:2023

RUN dnf update -y && \
    dnf install -y python3-pip && \
    dnf clean all

WORKDIR /app
COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt
COPY app.py ./

EXPOSE 8080
CMD ["python3", "app.py"]
