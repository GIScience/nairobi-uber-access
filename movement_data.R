# Head ---------------------------------
# purpose: Script to prepare all datasets
# author: Marcel
#
#
#1 Libraries ---------------------------------

library(httr)
library(sf)
library(osmdata)
library(mapview)
library(glue)
library(dplyr)
library(tidyverse)
library(tictoc)
library(googlePolylines)



#2 Functions ---------------------------------

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

#3 setup ---------------------------------

if (!dir.exists("data")) {
  dir.create("data")
}


#4 Prep and preprocess data ---------------------------------

# Nairobi Boundary
if (!file.exists("data/nairobi_boundary.gpkg")) {
  nairobi <- opq(bbox = 'Nairobi, Kenya') |>
    add_osm_feature(key = 'name', value = 'Nairobi') |>
    add_osm_feature(key = 'admin_level', value = '3') |>
    osmdata_sf()
  nairobi_boundary <- nairobi$osm_multipolygons

  nairobi_boundary |> st_write("data/nairobi_boundary.gpkg", append=F)
} else {
  nairobi_boundary <- st_read("data/nairobi_boundary.gpkg", quiet=T)
}

# Nairobi Wards
# DL from HDX: https://data.humdata.org/dataset/administrative-wards-in-kenya-1450
if (!file.exists("data/Kenya_Wards/kenya_wards.shp")) {
  stop("Sorry no option to auto dl the Wards Dataset.\nVisit  https://data.humdata.org/dataset/administrative-wards-in-kenya-1450 for to download\nand unzip it into data/")
} else {
  kenya_wards <- st_read("data/Kenya_Wards/kenya_wards.shp", quiet=T)
}

# Add cenroid for wards
kenya_wards <- kenya_wards |>
  st_make_valid()
kenya_wards$centroid <- kenya_wards |>
  st_point_on_surface()

# Buffer bounday by 5km
nairobi_boundary_buff <- nairobi_boundary |>
  st_transform(32737) |>
  st_buffer(5000) |>
  st_transform(4326)

# Create extent sf object
nairobi_extent <- st_sf(
  geometry = nairobi_boundary |>
    st_bbox() |>
    st_as_sfc() |>
    st_set_crs(st_crs(nairobi_boundary)))

# Create hexagonal grid sf object
hex_grid <- st_sf(
  geometry = nairobi_boundary |>
    st_transform(32737) |>
    st_make_grid(cellsize = 2000, square = F) |>
    st_transform(4326)
)  |> st_filter(nairobi_boundary)

hex_grid <-
  st_sf(
    hex_id = row_number(hex_grid),
    geometry = hex_grid$geom,
    centroid = st_centroid(hex_grid$geom)
  )

# Join ward names to grid
hex_grid_centroid <-
  st_sf(hex_id = hex_grid$hex_id, geometry = hex_grid$centroid)
hex_grid_centroid <- hex_grid_centroid |>  st_join(kenya_wards)
hex_grid <-
  hex_grid |> left_join(hex_grid_centroid |> data.frame() |> select(c(hex_id, gid, county, subcounty, ward)), by = "hex_id")

plot(hex_grid["ward"] |> st_geometry(), lwd=.1)
plot(nairobi_boundary |> st_geometry(), add=T)


st_write(hex_grid, "hex_grid.gpkg", append=F)


# Get schools

# TODO check better ways to identify schools

# osm_schools <- opq(bbox = 'Nairobi, Kenya') |>
#   add_osm_feature(key = 'amenity', value = 'school') |>
#   osmdata_sf()
#
# # How many school points do not overlap with school polygons
# osm_schools$osm_points |>
#   filter(!st_intersects(osm_schools$osm_polygons$geometry
#                         |> st_union(), sparse = F)) |>
#   nrow()
#
# # How many school polygons do not overlap with school multipolygons/relations
# osm_schools$osm_polygons |>
#   st_point_on_surface() |>
#   filter(!st_intersects(osm_schools$osm_multipolygons$geometry |>
#                           st_union(), sparse = F)) |>
#   nrow()
#
# schools <- osm_schools$osm_polygons |>
#   st_point_on_surface() |>
#   st_filter(nairobi_boundary)




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
  for (t in nrow(hex_grid):(i+1)) {
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
