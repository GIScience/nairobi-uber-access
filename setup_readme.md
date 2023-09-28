# Setup

This md file describes the steps to setup a local openrouteservice instance via docker with capabilities to consume uber traffic data for the city of Nairobi.

## Get openrouteservice locally

Clone the openrouteservice github repo:

`git clone https://github.com/GIScience/openrouteservice`

Now checkout branch with uber integration: 

`git checkout implement_uber_traffic`


Change the `openrouteservice/docker/docker-compose.yml` to fit the following:

```
version: '2.4'
services:
  ors-app:
    container_name: ors-app
    ports:
      - "8080:8080"
      - "9001:9001"
#    image: openrouteservice/openrouteservice:latest
    user: "${UID:-0}:${GID:-0}"
    build:
      context: ../
      args:
        ORS_CONFIG: ./openrouteservice/src/main/resources/ors-config-sample.json
        OSM_FILE: ./openrouteservice/src/main/files/heidelberg.osm.gz
    volumes:
      - ./graphs:/home/ors/ors-core/data/graphs
      - ./elevation_cache:/home/ors/ors-core/data/elevation_cache
      - ./logs/ors:/home/ors/ors-core/logs/ors
      - ./logs/tomcat:/home/ors/tomcat/logs
      - ./conf:/home/ors/ors-conf
      - ./nairobi_2019_06.osm.pbf:/home/ors/ors-core/data/osm_file.pbf
      - ./semester_ors.csv:/home/ors/ors-core/data/uber_traffic.csv
      #- ./your_osm.pbf:/home/ors/ors-core/data/osm_file.pbf
    environment:
      - BUILD_GRAPHS=False  # Forces the container to rebuild the graphs, e.g. when PBF is changed
      - "JAVA_OPTS=-Djava.awt.headless=true -server -XX:TargetSurvivorRatio=75 -XX:SurvivorRatio=64 -XX:MaxTenuringThreshold=3 -XX:+UseG1GC -XX:+ScavengeBeforeFullGC -XX:ParallelGCThreads=4 -Xms4g -Xmx12g"
      - "CATALINA_OPTS=-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9001 -Dcom.sun.management.jmxremote.rmi.port=9001 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=localhost"
```

Review the following lines:

`- ./nairobi_2019_06.osm.pbf:/home/ors/ors-core/data/osm_file.pbf` This points to the osm pbf to be used to create the routing graph inside openrouteservice. The file it is pointing from will be created next.

`- ./semester_ors.csv:/home/ors/ors-core/data/uber_traffic.csv` This points to the uber speeds table which will be used to enrich the routing graph. We create the file in the following.


## Prepare the osm road network (pbf)

**Download from geofabrik**

Authorize via your openstreetmap account.

https://osm-internal.download.geofabrik.de/

Download the full OSM history pbf.

https://osm-internal.download.geofabrik.de/africa/kenya.html

`wget https://osm-internal.download.geofabrik.de/africa/kenya-internal.osh.pbf --output-document=docker/kenya-internal.osh.pbf`

**Filter pbf temporal and spatially**

`osmium time-filter -o kenya_2019_06.osm.pbf kenya-internal.osh.pbf 2019-06-30T00:00:00Z`

`osmium extract -b 36.619794,-1.490089,37.149790,-1.115470 kenya_2019_06.osm.pbf -o nairobi_2019_06.osm.pbf --overwrite`



## Prepare Uber traffic data 

Uber provides us with different data products for traffic speeds in Nairobi. 
All available here: https://movement.uber.com/cities/nairobi/downloads/speeds?lang=en-US&tp%5By%5D=2018&tp%5Bq%5D=4

**TODO Charlie please review and update.**

Download all monthly speed traffic data for 2019.
Then run the script <script name>.




Put all files inside the `openrouteservice/docker` directory.

```
docker
├── docker-compose.yml
├── kenya_2019_06.osm.pbf
├── kenya-internal.osh.pbf
├── semester_ors.csv
└── nairobi_2019_06.osm.pbf
```

## Run openrouteservice docker 

Create volume directories:

```
openrouteservice/docker $ mkdir -p conf elevation_cache graphs logs/ors logs/tomcat
```

Start up via docker compose

```
openrouteservice/docker $ ORS_UID=${UID} ORS_GID=${GID} docker compose up
```


Check availability via

```
$ curl localhost:8080/ors/v2/health
```

## Routing Requests

**Route 6AM**

```
curl --location 'http://localhost:8080/ors/v2/directions/driving-car' \
--header 'Content-Type: application/json' \
--data '{
    "coordinates":[[36.95397377014161, -1.2530281581017089],[36.77184104919434, -1.2694178479317129]],
    "arrival": "2018-02-23T06:00:00",
    "instructions": false
}'
```

Response

```
..
    "routes": [
        {
            "summary": {
                "distance": 26876.6,
                "duration": 2375.1
            },
..
```


**Route 10AM**

```
curl --location 'http://localhost:8080/ors/v2/directions/driving-car' \
--header 'Content-Type: application/json' \
--data '{
    "coordinates":[[36.95397377014161, -1.2530281581017089],[36.77184104919434, -1.2694178479317129]],
    "arrival": "2018-02-23T10:00:00",
    "instructions": false
}'
```

Response

```
..
    "routes": [
        {
            "summary": {
                "distance": 26953.4,
                "duration": 2974.2
            },
..
```




