# Setup

This md file describes the steps to setup a local openrouteservice instance via docker with capabilities to consume uber traffic data for the city of Nairobi.

## Get openrouteservice locally

setup ors + uber locally:

clone ors github repo `git clone https://github.com/GIScience/openrouteservice`

Next checkout branch with uber integration: `git checkout implement_uber_traffic`

docker-compose.yml

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
      - ./school_morn_ors.csv:/home/ors/ors-core/data/uber_traffic.csv
      #- ./your_osm.pbf:/home/ors/ors-core/data/osm_file.pbf
    environment:
      - BUILD_GRAPHS=False  # Forces the container to rebuild the graphs, e.g. when PBF is changed
      - "JAVA_OPTS=-Djava.awt.headless=true -server -XX:TargetSurvivorRatio=75 -XX:SurvivorRatio=64 -XX:MaxTenuringThreshold=3 -XX:+UseG1GC -XX:+ScavengeBeforeFullGC -XX:ParallelGCThreads=4 -Xms4g -Xmx8g"
      - "CATALINA_OPTS=-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9001 -Dcom.sun.management.jmxremote.rmi.port=9001 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=localhost"
```

Make changes to the following files:

_openrouteservice/src/main/resources/ors-config-sample.json_

Line 206

```
...
}
"ext_storages": {
    "UberTraffic": {
        "enabled": true,
         "movement_data": "/home/ors/ors-core/data/uber_traffic.csv",
         "output_log": true
    },
    "WayCategory": {},
    "HeavyVehicle": {},
    "WaySurfaceType": {},
...
```

_openrouteservice/src/main/java/org/heigit/ors/routing/graphhopper/extensions/storages/AbstractTrafficGraphStorage.java_

Line 23

```
    private ZoneId zoneId = ZoneId.of("Africa/Addis_Ababa");
```


## Get osm road network

**Download from geofabrik**

Authorize via your openstreetmap account

https://osm-internal.download.geofabrik.de/

Download the full OSM history pbf.

https://osm-internal.download.geofabrik.de/africa/kenya.html

`wget https://osm-internal.download.geofabrik.de/africa/kenya-internal.osh.pbf --output-document=docker/kenya-internal.osh.pbf`

`osmium time-filter -o kenya_2019_06.osm.pbf kenya-internal.osh.pbf 2019-06-30T00:00:00Z`

`osmium extract -b 36.619794,-1.490089,37.149790,-1.115470 kenya_2019_06.osm.pbf -o nairobi_2019_06.osm.pbf --overwrite`



## Download Uber traffic data 

Get the _Quarterly Speeds Statistics by Hour of Day (Q2 2018)_

**For our analysis we use preprocessed speed values**

Available here https://heibox.uni-heidelberg.de/seafhttp/files/0058862b-858b-43b7-a5cf-a072f678e229/nairobi_ors.zip

https://movement.uber.com/cities/nairobi/downloads/speeds?lang=en-US&tp[y]=2018&tp[q]=2


Put all files inside the `openrouteservice/docker` directory.

```
docker
├── docker-compose.yml
├── kenya_2018_Q2.osm.pbf
├── kenya-internal.osh.pbf
├── kenya-latest.osm.pbf
├── movement-speeds-quarterly-by-hod-nairobi-2018-Q2.csv
└── nairobi_2018_Q2.osm.pbf
```

## Run openrouteservice docker 

Create volume directories:

```
openrouteservice $ mkdir -p docker/conf docker/elevation_cache docker/graphs docker/logs/ors docker/logs/tomcat
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




