FROM osgeo/gdal:ubuntu-small-3.1.2

# install tippecanoe
RUN apt-get update \
  && apt-get -y upgrade \
  && apt-get install -y build-essential git libsqlite3-dev zlib1g-dev
RUN git clone https://github.com/mapbox/tippecanoe.git && \
  cd tippecanoe && make -j && make install

COPY scripts/run_tippecanoe.sh /opt
RUN chmod +x /opt/run_tippecanoe.sh

# install mbview
ARG NODE_VERSION=14
RUN curl -sL https://deb.nodesource.com/setup_${NODE_VERSION}.x  | bash -
RUN apt-get -y install nodejs
RUN npm install -g --unsafe-perm @mapbox/mbview
EXPOSE 3000

