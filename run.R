# Head ---------------------------------
# purpose: Script which runs the
# author: Marcel
#
#
#1 Libraries & functions ---------------------------------

library(tidyverse)
library(sf)
library(osmdata)
source("fun.R")

#2 Generate routes ---------------------------------

period <- "semester" # changes this according to which uber CSVs you have currently loaded in your openrouteservice
# period <- "holiday"
hex_grid <- readRDS("hex_grid.rds")



tic("run ")
plan(multisession, workers = 12)
routes <- get_routes (
  origins = hex_grid$centroid,
  origin_ids = hex_grid$hex_id,
  #destinations = hex_grid_dests$centroid,
  #dest_ids = hex_grid_dests$hex_id,
  arrivals=c("2019-04-11T08:00:00", "2019-04-11T16:00:00")
)
toc()

saveRDS(routes, paste0(period,"_", hex_grid |> nrow(), ",.rds"))


#3 Assess output ---------------------------------


semester_routes <- readRDS(paste0(period,"_", hex_grid |> nrow(), ",.rds"))
holiday_routes <- readRDS(paste0(period,"_", hex_grid |> nrow(), ",.rds"))

holiday_routes$cat <- "holiday"
semester_routes$cat <- "semester"

semester_routes$duration_diff <- semester_routes$duration - holiday_routes$duration
semester_routes$distance_diff <- semester_routes$distance - holiday_routes$distance

holiday_routes$duration_diff <- holiday_routes$duration - semester_routes$duration
holiday_routes$distance_diff <- holiday_routes$distance - semester_routes$distance

routes <- bind_rows(holiday_routes,
                    semester_routes)

routes_agg <- routes |> group_by(cat, requested_arrival, origin_id) |>
  summarise(
    duration_diff_sum = sum(duration_diff, na.rm = T),
    duration_diff_avg = mean(duration_diff, na.rm = T),
    duration_diff_min = min(duration_diff, na.rm = T),
    duration_diff_max = max(duration_diff, na.rm = T),
    duration_diff_median = median(duration_diff, na.rm = T),
    duration_diff_q25 =quantile(duration_diff, probs = 0.25, na.rm = T),
    duration_diff_q75 =quantile(duration_diff, probs = 0.75, na.rm = T)
  ) |> ungroup()

hex_grid_join <- hex_grid |> left_join(routes_agg, by = c("hex_id"="origin_id"))



tm_shape(hex_grid_join) +
  tm_polygons(
    "duration_diff_median",
    palette = "BrBG",
    n = 5,
    breaks = c(-500, -50, 0, 50, 500),
  ) +
  tm_facets(by = c("cat", "requested_arrival"),
            free.scales = F)
