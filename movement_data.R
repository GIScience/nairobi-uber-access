
library(httr)

library(sf)
library(osmdata)
library(mapview)
library(glue)
library(plyr)
library(dplyr)
library(tidyverse)
library(tictoc)
library(googlePolylines)



gp2sf <- function(gp) {
  gp |>
    googlePolylines::decode() |>
    map_dfr(
      function(df) {
        df |>
          st_as_sf(coords = c("lon", "lat")) |>
          st_combine() |>
          st_cast("LINESTRING") |>
          st_sf()
      }) |>
    pull(1)
}

if (!file.exists("data/nairobi_boundary.gpkg")) {
  nairobi <- opq(bbox = 'Nairobi, Kenya') |>
    add_osm_feature(key = 'name', value = 'Nairobi') |>
    add_osm_feature(key = 'admin_level', value = '3') |>
    osmdata_sf()
  nairobi_boundary <- nairobi$osm_multipolygons


  #library(rgeoboundaries)
  #nairobi_boundary <- gb_adm1("Kenya") |> filter(shapeName=="Nairobi")

  nairobi_boundary |> st_write("data/nairobi_boundary.gpkg", append=F)
} else {
  nairobi_boundary <- st_read("data/nairobi_boundary.gpkg")
}


#kenya_wards <- gb_adm4("Kenya")
kenya_wards <- st_read("data/Kenya_Wards/kenya_wards.shp")
kenya_wards <- kenya_wards |> st_make_valid()
kenya_wards$centroid <- kenya_wards |> st_point_on_surface()

nairobi_boundary_buff <- nairobi_boundary |> st_transform(32737) |> st_buffer(10000) |> st_transform(4326)

nairobi_extent <- nairobi_boundary |> st_bbox() |> st_as_sfc() |> st_set_crs( st_crs(nairobi_boundary))

hex_grid <- nairobi_boundary |> st_transform(32737) |>  st_make_grid(cellsize = 5000, square = F) |> st_transform(4326)
hex_grid <- st_sf(geom=hex_grid)

hex_grid <- hex_grid |> st_filter(nairobi_boundary)

hex_grid <- st_sf(rnr=row_number(hex_grid), geom=hex_grid$geom, centroid=st_centroid(hex_grid$geom))

nrow(hex_grid)
nrow(kenya_wards)

kenya_wards

hex_grid_centroid <- st_sf(rnr=hex_grid$rnr, geom=hex_grid$centroid)
hex_grid_centroid <- hex_grid_centroid |>  st_join(kenya_wards)
hex_grid <- hex_grid |> left_join(hex_grid_centroid |> data.frame() |> select(c(rnr,gid,county,subcounty,ward)), by = "rnr")

nrow(hex_grid)

plot(hex_grid["ward"] |> st_geometry(), lwd=.1)
plot(nairobi_boundary |> st_geometry(), add=T)

#st_write(hex_grid, "hex_grid.gpkg", append=F)


tic.clear()
# loop through hexgrid
result <- data.frame(bbox=NA, geometry=NA, way_points=NA, legs=NA, departure=NA, arrival=NA, geom=NA, status=NA, id_origin=NA, id_destination=NA, distance=NA,duration=NA)

n = 15
tic("first n")
for (i in 1:n) {
#for (i in 1:nrow(hex_grid)) {
  #i <- 1
  tic(glue("run {i} / {nrow(hex_grid)}"))
  origin <- hex_grid[i,]

  #for (t in nrow(hex_grid):1) {
  for (t in nrow(hex_grid):i+1) {
    #t <- 264
    if (i == t) {next}

    destination <- hex_grid[t,]

    headers = c(
      'Content-Type' = 'application/json'
    )

    or_coord <-origin$centroid |> st_coordinates() |> as.numeric()
    dest_coord <- destination$centroid |> st_coordinates() |> as.numeric()

    #body = '{"coordinates": [[' + ',-1.2530281581017089],[36.77184104919434,-1.2694178479317129]], "arrival": "2018-02-23T06:00:00","instructions": false}'
    body <- list(coordinates=list(c(or_coord[1],or_coord[2]),
                          c(dest_coord[1],dest_coord[2])),
         arrival="2018-02-23T06:00:00",
         instructions=F) |> jsonlite::toJSON(auto_unbox = T)

    # check if POST is faster than VERB
    res <- VERB("POST", url = "http://localhost:8080/ors/v2/directions/driving-car", body = body, add_headers(headers))
    print(glue(" run i {i}; run {t}, {res$status_code}"))
    if (res$status_code!=200) {

      df_resp <- data.frame(status=res$status_code)
      df_resp$id_origin <- i
      df_resp$id_destination <- t
      # alternative: bind_rows
      result <- rbind.fill(result, df_resp)
      rm(res,df_resp)
      print(glue(" rows: {nrow(result)}"))

    } else {
      json_resp <- res$content |> rawToChar() |> jsonlite::fromJSON()
      df_resp <- json_resp$routes |> as.data.frame()


      df_resp <- df_resp |> mutate(geom = gp2sf(geometry)) |>
        st_sf(crs = "EPSG:4326")



      df_resp$id_origin <- i
      df_resp$id_destination <- t
      df_resp$status <- res$status_code
      df_resp$distance <- df_resp$summary$distance
      df_resp$duration <- df_resp$summary$duration
      df_resp <- df_resp |> select(-c(summary))
      result |>  names()
      df_resp |>  names()
      result <- rbind.fill(result,
                           df_resp |> select(bbox, geometry, way_points, legs, departure, arrival, geom, status, id_origin, id_destination, distance, duration))

      rm(df_resp,res, json_resp)
      print(glue(" rows: {nrow(result)}"))
      }

  }
  toc()
}
toc()
