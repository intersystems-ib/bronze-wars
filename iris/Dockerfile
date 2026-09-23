ARG IMAGE=docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2026.2.0AI.162.0
FROM $IMAGE

USER root

WORKDIR /opt/irisapp
RUN chown -R ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_MGRUSER} /opt/irisapp

USER ${ISC_PACKAGE_MGRUSER}

COPY /iris/src src

ENV PIP_ROOT_USER_ACTION=ignore

COPY --chown=$ISC_PACKAGE_MGRUSER:$ISC_PACKAGE_IRISGROUP /iris/requirements.txt /
RUN chmod 777 /requirements.txt

RUN pip3 install -r /requirements.txt --break-system-packages --no-cache-dir

COPY --chown=$ISC_PACKAGE_MGRUSER:$ISC_PACKAGE_IRISGROUP /iris/iris.cpf /
RUN chmod +x /iris.cpf

ENV ISC_CPF_MERGE_FILE=/iris.cpf

# copy files to image
WORKDIR /opt/irisapp
COPY --chown=irisowner:irisowner iris/iris.script iris.script

# run iris.script
RUN iris start IRIS \
    && iris session IRIS < /opt/irisapp/iris.script \
    && iris stop IRIS quietly