# Head ---------------------------------
# purpose: Script which runs the
# author: Marcel
#
#
#1 Libraries & functions ---------------------------------

library(tidyverse)
library(sf)
library(osmdata)
library(tmap)
library(ggplot2)
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


semester_routes <- readRDS(paste0("semester_", hex_grid |> nrow(), ".rds"))
holiday_routes <- readRDS(paste0("holiday_", hex_grid |> nrow(), ".rds"))

holiday_routes$cat <- "holiday"
semester_routes$cat <- "semester"

semester_routes$duration_diff <- semester_routes$duration - holiday_routes$duration
semester_routes$distance_diff <- semester_routes$distance - holiday_routes$distance

holiday_routes$duration_diff <- holiday_routes$duration - semester_routes$duration
holiday_routes$distance_diff <- holiday_routes$distance - semester_routes$distance

routes <- bind_rows(holiday_routes,
                    semester_routes)

#4 Non-spatial ---------------------------------

routes <- routes |>
  mutate(time=as.factor(case_when(
    requested_arrival == "2019-04-11T08:00:00" ~ 8,
    requested_arrival == "2019-04-11T16:00:00" ~ 16,
  )))

mu <- routes |> group_by(cat, time) |>
  summarise(grp.mean = mean(duration_diff, na.rm=T))


routes |> filter(cat=="semester") |>  ggplot(
  aes(x = duration_diff,
      color = time,
      fill = time))+ geom_histogram(aes(y = ..density..),
                                                 position = "identity", alpha = 0.5) +
  geom_density(alpha = 0.6) +
  geom_vline(
    data = mu |> filter(cat=="semester"),
    aes(xintercept = grp.mean, color = time),
    linetype = "dashed"
  ) +
  labs(title = "Distance histogram", x = "Distance", y = "Density")

# random pick of origin 40
routes |>
  filter(cat=="semester" & origin_id==140) |>
  ggplot(aes(x=distance, y=duration_diff, group=time)) +
  #geom_line(aes(color=time)) +
  geom_smooth(aes(color=time)) +
  theme_light()


# lets do some aggregations
routes_agg <- routes |> group_by(cat, time, origin_id) |>
  summarise(
    duration_diff_sum = sum(duration_diff, na.rm = T),
    duration_diff_avg = mean(duration_diff, na.rm = T),
    duration_diff_min = min(duration_diff, na.rm = T),
    duration_diff_max = max(duration_diff, na.rm = T),
    duration_diff_median = median(duration_diff, na.rm = T),
    duration_diff_q25 =quantile(duration_diff, probs = 0.25, na.rm = T),
    duration_diff_q75 =quantile(duration_diff, probs = 0.75, na.rm = T)
  ) |> ungroup()


ioi <- data.frame(bind_rows(
  routes_agg |> filter(cat=="semester") |> arrange(duration_diff_avg) |> head(5) |> select(origin_id),
  routes_agg |> filter(cat=="semester" & !is.nan(duration_diff_avg)) |> arrange(duration_diff_avg) |> tail(5) |> select(origin_id),
  routes_agg |> filter(cat=="semester") |> arrange(abs(duration_diff_avg)) |> head(5) |> select(origin_id)
), type=c(rep("avg.increase",5),
          rep("avg.decrease",5),
          rep("avg.neutral",5)))


routes |> inner_join(ioi, by = c("origin_id"="origin_id"))


routes |>
  #filter(cat=="semester" & origin_id %in% ioi$origin_id) |>
  filter(cat=="semester") |>
  right_join(ioi, by = c("origin_id"="origin_id")) |>
  ggplot(aes(x=distance, y=duration_diff, group=time)) +
  #geom_line(aes(color=time)) +
  #geom_point(aes(color=time)) +
  geom_smooth(aes(color=time)) +
  facet_grid(~origin_id, cols = 5) +
  #facet_grid(cols =vars(origin_id), rows=vars(type)) +
  theme_light()


#5 Spatial ---------------------------------



hex_grid_join <- hex_grid |> left_join(routes_agg, by = c("hex_id"="origin_id"))
hex_grid_join |> filter(cat=="semester") |> nrow()

st_write(hex_grid_join, "hex_grid_join172.gpkg", append=F)

tm_shape(hex_grid_join) +
  tm_polygons(
    "duration_diff_avg",
    palette = "BrBG",
    #n = 5,
    breaks = c(-500, -10, 0, 10, 500),
  ) +
  tm_layout(asp=1) +
  tm_facets(by = c("cat", "time"),
            free.scales = F)
