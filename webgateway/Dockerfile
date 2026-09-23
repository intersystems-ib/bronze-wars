ARG IMAGE=containers.intersystems.com/intersystems/webgateway:latest-em
FROM $IMAGE

RUN apt-get update
RUN apt-get install -y build-essential cmake zlib1g-dev libcppunit-dev git subversion wget && rm -rf /var/lib/apt/lists/*
