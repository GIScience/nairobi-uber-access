# Head ---------------------------------
# purpose: Script to prepare all datasets
# author: Marcel
#
#
#1 Libraries ---------------------------------

library(tidyverse)
library(sf)
library(osmdata)

#2 Main ---------------------------------




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
    st_make_grid(cellsize = 2500, square = F) |>
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

#plot(hex_grid["ward"] |> st_geometry(), lwd=.1)
#plot(nairobi_boundary |> st_geometry(), add=T)

osm_schools <- opq(bbox = nairobi_extent |> st_bbox() |> as.numeric()) |>
  add_osm_feature(key = 'amenity', value = 'school') |>
  osmdata_sf()

osm_schools_merge  <- osm_schools$osm_points |> bind_rows(
  osm_schools$osm_polygons |> st_point_on_surface(),
  osm_schools$osm_multipolygons |> st_point_on_surface()
)
#hex_grid$schools_count <- st_intersects(hex_grid$geometry, osm_schools_merge) |> lengths()
hex_grid$schools_count <- st_intersects(hex_grid$geom, osm_schools_merge) |> lengths()


st_write(hex_grid, "hex_grid.gpkg", append=F)
saveRDS(hex_grid, "hex_grid.rds")

hex_grid <- st_read("hex_grid.gpkg")
#hex_grid <- hex_grid[1:10,]
hex_grid <- readRDS("hex_grid.rds")
